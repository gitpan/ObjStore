#include "osperl.h"

// Since perl_exception has no parent and is never signalled, we always
// get an unhandled exception when ObjectStore throws.
DEFINE_EXCEPTION(perl_exception,"Perl/ObjStore Exception",0);

/*--------------------------------------------- per-thread context */

osp_thr *global_osp_context = 0;
osp_thr *osp_thr::fetch()
{ return global_osp_context; }

void osp_thr::boot_single()
{
  objectstore::set_thread_locking(0);
  global_osp_context = new osp_thr;
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
    SV *hdlr = perl_get_sv("ObjStore::EXCEPTION", 0);
    assert(hdlr);
    osp->handler._unwind_part_2(); //??
    perl_call_sv(hdlr, G_DISCARD);
  }
}

osp_thr::osp_thr()
  : handler(&perl_exception)
{
  debug = 0;
  CLASSLOAD = perl_get_hv("ObjStore::CLASSLOAD", FALSE);// will need to lock XXX
  assert(CLASSLOAD);
  stargate = 0;
  tie_objects = 1;
  txn = 0;
  tix_exception::set_unhandled_exception_hook(ehook);
}

osp_thr::~osp_thr()
{
  //free stargate XXX
}

int osp_thr::can_update()
{ return txn && txn->can_update(); }

/*--------------------------------------------- ossv_bridge */

ossv_bridge::ossv_bridge(OSSVPV *_pv)
  : pv(_pv)
{
  dOSP ; dTXN ;
  assert(pv);
  DEBUG_bridge(warn("ossv_bridge 0x%x->new(%s=0x%x)",
		    this, _pv->base_class(), _pv));
  if (txn->can_update()) pv->REF_inc();

  prev = 0;
  if (txn->bridge_top) {
    txn->bridge_top->prev = this;
    next = txn->bridge_top;
    txn->bridge_top = this;
  } else {
    next = 0;
    txn->bridge_top = this;
  }
}

// Must be able to remove itself from the list
void ossv_bridge::invalidate()
{
  dOSP ; dTXN ;
  if (!pv) return;

  // do everything, then REF_dec to avoid race condition
  OSSVPV *copy = pv; pv=0;  
  if (next) next->prev = prev;
  if (prev) prev->next = next;
  if (txn->bridge_top == this) {
    if (next) txn->bridge_top = next;
    else txn->bridge_top = prev;
  }

  DEBUG_bridge(warn("ossv_bridge 0x%x->invalidate(pv=0x%x) updt=%d",
		    this, copy, txn->can_update()));
  if (txn->can_update()) copy->REF_dec();
}

ossv_bridge::~ossv_bridge()
{ invalidate(); }

void ossv_bridge::dump()
{ warn("ossv_bridge=0x%x pv=0x%x", this, pv); }

OSSVPV *ossv_bridge::ospv()
{
  if (!pv) croak("Attempt to use bridge 0x%p out of scope", this);
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
  os = os_transaction::begin(tt, scope_in);
  bridge_top = 0;
  got_os_exception = 0;
  deadlocked = 0;

  up = osp->txn;
  osp->txn = this;
  DEBUG_txn(warn("%p->new", this));
}

osp_txn::~osp_txn()
{
  DEBUG_txn(warn("%p->~osp_txn", this));
  dOSP ;
  osp->txn = up;
  up=0;
}

void osp_txn::prepare_to_commit()
{dOSP ; dTXN ; assert(txn && txn->os); txn->os->prepare_to_commit(); }
int osp_txn::is_prepare_to_commit_invoked()
{dOSP ; dTXN ; assert(txn && txn->os);
 return txn->os->is_prepare_to_commit_invoked();}
int osp_txn::is_prepare_to_commit_completed()
{dOSP ; dTXN ; assert(txn && txn->os);
 return txn->os->is_prepare_to_commit_completed();}

void osp_txn::post_transaction()
{
/* After the transaction is complete, post_transaction() is called
   twice, before the eval unwinds and after. */

  DEBUG_txn(warn("%p->post_transaction", this));

  while (1) {
    ossv_bridge *br = bridge_top;
    if (!br) break;
    br->invalidate();
  }
  assert(bridge_top==0);

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
    DEBUG_txn(warn("abort"));
    os_transaction::abort(os);
  }
  delete os;
  os=0;
}

void osp_txn::commit()
{
  if (!os) return;
  if (!os->is_aborted()) {
    DEBUG_txn(warn("commit"));
    os_transaction::commit(os);
  }
  delete os;
  os=0;
}
