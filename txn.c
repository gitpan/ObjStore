#include "osperl.h"

// Since perl_exception has no parent and is never signalled, we always
// get an unhandled exception when ObjectStore throws.
DEFINE_EXCEPTION(perl_exception,"Perl/ObjStore Exception",0);

/*--------------------------------------------- per-thread context */

int osp_thr::info_key;

osp_thr *osp_thr::fetch()
{
#if !defined(USE_THREADS)
  static osp_thr *single_thread = 0;
  if (!single_thread) single_thread = new osp_thr;
  return single_thread;
#else
  dTHR;
  assert(thr->specific);
  SV *info = * av_fetch(thr->specific, info_key, 1);
  assert(info);
  if (!SvIOK(info)) {
    DEBUG_thread(warn("ObjStore: creating info for thread %p at %d",
		      thr, info_key));
    sv_setiv(info, (IV) new osp_thr);
    SvREFCNT_inc(info);
  }
  return (osp_thr*) SvIV(info);
#endif
}

static void ehook(tix_exception_p cause, os_int32 value, os_char_p report)
{
  dOSP ; dTXN ;
  if (txn) {	//assume worst case, SEGV
    DEBUG_txn(warn("before sighandler(SEGV): %s", report));

    txn->got_os_exception=1;
    txn->report = report;
    txn->handler._unwind_part_1(cause, value, report);
    Perl_sighandler(SIGSEGV);

  } else {
    DEBUG_txn(warn("before &EXCEPTION: %s", report));

    osp->handler._unwind_part_1(cause, value, report);
    dSP ;
    PUSHMARK(sp) ;
    XPUSHs(sv_2mortal(newSVpv(report, 0)));
    PUTBACK;
    osp->handler._unwind_part_2(); //??
    SV *hdlr = perl_get_sv("ObjStore::EXCEPTION", 0);
    assert(hdlr);
    perl_call_sv(hdlr, G_DISCARD);
  }
}

osp_thr::osp_thr()
  : handler(&perl_exception)
{
  debug = 0;
  errsv = newSVpv("",0);
  CLASSLOAD = perl_get_hv("ObjStore::CLASSLOAD", FALSE);// will need to lock XXX
  assert(CLASSLOAD);
  stargate = 0;
  tie_objects = 1;
  txn = 0;
  tix_exception::set_unhandled_exception_hook(ehook);
  bridge_top = 0;
}

void osp_thr::destroy_bridge()
{
  ossv_bridge *br = bridge_top;
  bridge_top=0;
  while (br) {
    ossv_bridge *nxt = br->next;
    if (br->ready()) delete br;
    else {
      br->next = bridge_top;
      bridge_top = br;
    }
    br = nxt;
  }
}

osp_thr::~osp_thr()
{
  //free stargate XXX
  //free errsv 
}

int osp_thr::can_update()
{ return txn && txn->can_update(); }

/*
void osp_thr::invalidate(OSSVPV *pv)
{
  // nuke? XXX
  int reps=0;
  DEBUG_txn(warn("thr(%p)->invalidate(%p): enter", this, pv));
  osp_txn *tx = txn;
  while (tx) {
    tx->invalidate(pv);
    tx = tx->up;
    if (reps++ > 1000)
      croak("thr(%p)->invalidate: loop detected", this);
  }
  DEBUG_txn(warn("thr(%p)->invalidate(%p): exit", this, pv));
}
*/

/*--------------------------------------------- ossv_bridge */

ossv_bridge::ossv_bridge(OSSVPV *_pv)
  : pv(_pv)
{
  is_transient = os_segment::of(pv) == os_segment::of(0);
  is_strong_ref = 1;
  can_delete = 0;

  dOSP ; dTXN ;
  assert(pv);
  STRLEN junk;
  DEBUG_bridge(warn("ossv_bridge 0x%x->new(%s=0x%x) is_transient=%d",
		    this, _pv->os_class(&junk), pv, is_transient));
  if (txn->can_update()) pv->REF_inc();

  // add to TXN bridge
  next = txn->bridge_top;
  txn->bridge_top = this;
}

ossv_bridge::~ossv_bridge()
{
  if (!can_delete) croak("%p->~ossv_bridge: still valid");
  DEBUG_bridge(warn("ossv_bridge(0x%x)->DESTROY", this));
}

/*
void ossv_bridge::HOLD()
{
  if (is_strong_ref) return;
  if (!pv) croak("%p->HOLD(): too late; already lost reference", this);
  dOSP ; dTXN ;
  if (txn->can_update()) {
    DEBUG_bridge(warn("ossv_bridge 0x%x->HOLD(pv=0x%x) updt=%d",
		      this, pv, txn->can_update()));
    ++ is_strong_ref;
    pv->REF_inc();
    pv->wREF_dec();
  }
}
*/

int ossv_bridge::ready()
{ return can_delete && !pv; }

void ossv_bridge::release()
{
  DEBUG_bridge(warn("ossv_bridge 0x%x->release(pv=0x%x)", this, pv));
  unref(); can_delete = 1;
}

void ossv_bridge::unref()
{
  if (!pv) return;
  OSSVPV *copy = pv;  //avoid race condition
  pv=0;

  dOSP ; dTXN ;
  DEBUG_bridge(warn("ossv_bridge 0x%x->unref(pv=0x%x) updt=%d",
		    this, copy, txn->can_update()));
  if (txn->can_update()) {
    if (is_strong_ref) copy->REF_dec();
//    else               copy->wREF_dec();
  }
}

void ossv_bridge::invalidate(OSSVPV *it)
{
  if (is_transient || (it && pv != it)) return;
  unref();
}

void ossv_bridge::dump()
{ warn("ossv_bridge=0x%x pv=0x%x next=0x%x", this, pv, next); }

OSSVPV *ossv_bridge::ospv()
{
  if (!pv) croak("Attempt to use persistent variable out of scope (0x%p)", this);
  return pv;
}

void *ossv_bridge::get_location()
{ return pv; }

/*--------------------------------------------- per-transaction context */

osp_txn::osp_txn(os_transaction::transaction_type_enum _tt,
		 os_transaction::transaction_scope_enum scope_in)
  : handler(&perl_exception), tt(_tt)
{
  dOSP ;
  osp->destroy_bridge();

  os = os_transaction::begin(tt, scope_in);
  bridge_top = 0;
  got_os_exception = 0;
  deadlocked = 0;

  up = osp->txn;
  osp->txn = this;
  DEBUG_txn(warn("txn(%p)->new(%s, up=0x%p)", this,
		 tt==os_transaction::read_only? "read":
		 tt==os_transaction::update? "update":
		 tt==os_transaction::abort_only? "abort_only":
		 "unknown",
		 up));
}

osp_txn::~osp_txn()
{
  dOSP ;
  osp->txn = up;
  up=0;

  int moved=0;

  // invalidate; then delete or move to thread bridge
  ossv_bridge *br = bridge_top;
  while (br) {
    ossv_bridge *nxt = br->next;
    br->invalidate();
    if (br->ready()) delete br;
    else {
      ++ moved;
      br->next = osp->bridge_top;
      osp->bridge_top = br;
    }
    br = nxt;
  }
  DEBUG_txn(warn("txn(%p)->~osp_txn: up=0x%p moved=%d", this, up, moved));
}

void osp_txn::prepare_to_commit()
{dOSP ; dTXN ; assert(txn && txn->os); txn->os->prepare_to_commit(); }
int osp_txn::is_prepare_to_commit_invoked()
{dOSP ; dTXN ; assert(txn && txn->os);
 return txn->os->is_prepare_to_commit_invoked();}
int osp_txn::is_prepare_to_commit_completed()
{dOSP ; dTXN ; assert(txn && txn->os);
 return txn->os->is_prepare_to_commit_completed();}

/*
void osp_txn::invalidate(OSSVPV *pv)
{
  // nuke? XXX
  ossv_bridge *br = bridge_top;
  while (br) {
    br->invalidate(pv);
    br = br->next;
  }
}
*/

void osp_txn::post_transaction()
{
/* After the transaction is complete, post_transaction() is called
   twice, before the eval unwinds and after. */

  DEBUG_txn(warn("%p->post_transaction", this));

  ossv_bridge *br = bridge_top;
  while (br) {
    br->invalidate();
    br = br->next;
  }

  if (got_os_exception) {
    got_os_exception=0;
    report=0;
    handler._unwind_part_2();

    //deadlock?
    tix_exception *ex = handler.get_exception();
    if (ex && ex->ancestor_of(&err_deadlock)) {
      osp_txn *top = this;
      while (top->up) top = top->up;
      top->deadlocked=1;
      DEBUG_txn(warn("deadlock detected"));
    }
  }
}

int osp_txn::can_update()
{ return (os && !os->is_aborted() && tt != os_transaction::read_only); }

void osp_txn::abort()
{
  if (!os) return;
  if (!os->is_aborted()) {
    DEBUG_txn(warn("txn(%p)->abort", this));
    os_transaction::abort(os);
  }
  delete os;
  os=0;
}

void osp_txn::commit()
{
  if (!os) return;
  if (!os->is_aborted()) {
    DEBUG_txn(warn("txn(%p)->commit", this));
    os_transaction::commit(os);
  }
  delete os;
  os=0;
}
