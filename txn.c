#include "osperl.h"

/* CCov: off */

void osp_croak(const char* pat, ...)
{
  dSP;
  SV *msg = NEWSV(0,0);
  va_list args;
//  perl_require_pv("Carp.pm");
  va_start(args, pat);
  sv_vsetpvfn(msg, pat, strlen(pat), &args, Null(SV**), 0, Null(bool*));
  va_end(args);
  SvREADONLY_on(msg);
  SAVEFREESV(msg);
  PUSHMARK(sp);
  XPUSHs(msg);
  PUTBACK;
  perl_call_pv("Carp::croak", G_DISCARD);
}

/* CCov: on */

// Since perl_exception has no parent and is never signalled, we always
// get an unhandled exception when ObjectStore throws.
DEFINE_EXCEPTION(perl_exception,"Perl/ObjStore Exception",0);

/*--------------------------------------------- osp_bridge */

osp_bridge::osp_bridge()
{
  dOSP; dTXN;
  next = txn->bridge_top;
  txn->bridge_top = this;
}

osp_bridge::~osp_bridge()
{
//  assert(ready()); should be done in subclasses
  DEBUG_bridge(warn("bridge(%p)->DESTROY", this));
}
void osp_bridge::release()
{ croak("osp_bridge::release()"); }
void osp_bridge::invalidate()
{ croak("osp_bridge::invalidate()"); }
int osp_bridge::invalid()
{ croak("osp_bridge::invalid()"); return 1; }
int osp_bridge::ready()
{ croak("osp_bridge::ready()"); return 0; }

/*--------------------------------------------- per-thread context */

int osp_thr::info_key;

/* CCov: off */

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
    DEBUG_thread(warn("ObjStore: creating info for thread %p at [%d]",
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
  if (txn) {
    DEBUG_txn(warn("before sighandler(SEGV): %s", report));

    txn->got_os_exception=1;
    txn->report = report;
#ifndef _OS_CPP_EXCEPTIONS
    txn->handler._unwind_part_1(cause, value, report);
#endif
    Perl_sighandler(SIGSEGV);

  } else {
    // This should never happen XXX
    DEBUG_txn(warn("before &EXCEPTION: %s", report));

#ifndef _OS_CPP_EXCEPTIONS
    osp->handler._unwind_part_1(cause, value, report);
#endif
    dSP ;
    PUSHMARK(sp) ;
    XPUSHs(sv_2mortal(newSVpv(report, 0)));
    PUTBACK;
#ifndef _OS_CPP_EXCEPTIONS
    osp->handler._unwind_part_2(); //??
#endif
    SV *hdlr = perl_get_sv("ObjStore::EXCEPTION", 0);
    assert(hdlr);
    perl_call_sv(hdlr, G_DISCARD);
  }
}

/* CCov: on */

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
  osp_bridge *br = bridge_top;
  bridge_top=0;
  while (br) {
    osp_bridge *nxt = br->next;
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

int osp_thr::can_update(void *vptr)
{ return txn && txn->can_update(vptr); }

/*--------------------------------------------- per-transaction context */

osp_txn::osp_txn(os_transaction::transaction_type_enum _tt,
		 os_transaction::transaction_scope_enum scope_in)
  : handler(&perl_exception), tt(_tt)
{
  dOSP ;
  osp->destroy_bridge();

  report=0;
  os = os_transaction::begin(tt, scope_in);
  bridge_top = 0;
  got_os_exception = 0;
  deadlocked = 0; //XXX

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
  osp_bridge *br = bridge_top;
  while (br) {
    osp_bridge *nxt = br->next;
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

/* CCov:off */
// EXPERIMENTAL
void osp_txn::prepare_to_commit()
{dOSP ; dTXN ; assert(txn && txn->os); txn->os->prepare_to_commit(); }
int osp_txn::is_prepare_to_commit_invoked()
{dOSP ; dTXN ; assert(txn && txn->os);
 return txn->os->is_prepare_to_commit_invoked();}
int osp_txn::is_prepare_to_commit_completed()
{dOSP ; dTXN ; assert(txn && txn->os);
 return txn->os->is_prepare_to_commit_completed();}
/* CCov:on */

void osp_txn::post_transaction()
{
/* After the transaction is complete, post_transaction() is called
   twice, before the eval unwinds and after. */

  DEBUG_txn(warn("%p->post_transaction", this));

  osp_bridge *br = bridge_top;
  while (br) {
    br->invalidate();
    br = br->next;
  }

  if (got_os_exception) {
    got_os_exception=0;
    report=0;
#ifndef _OS_CPP_EXCEPTIONS
    handler._unwind_part_2();
#endif

    //deadlock?
    tix_exception *ex = handler.get_exception();
    if (ex && ex->ancestor_of(&err_deadlock)) {
      osp_txn *top = this;
      while (top->up) top = top->up;
      top->deadlocked=1; //XXX
      DEBUG_txn(warn("deadlock detected"));
    }
  }
}

int osp_txn::can_update(os_database *db)
{
  return (os && !os->is_aborted() && tt != os_transaction::read_only && 
	  db && db->is_writable());
}

int osp_txn::can_update(void *vptr)
{
  if (!os || os->is_aborted()) return 0;  //CAREFUL!  vptr might be invalid!
  os_database *db = os_database::of(vptr);
  return can_update(db);
}

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
