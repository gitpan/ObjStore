#include "osperl.h"
#include "XSthr.h"

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

/*--------------------------------------------- per-thread context */

/* CCov: off */

// Since perl_exception has no parent and is never signalled, we always
// get an unhandled exception when ObjectStore dies.
DEFINE_EXCEPTION(perl_exception,"Perl/ObjectStore Exception!",0);

// And here is our dynamically allocated tix_handler...!
dytix_handler::dytix_handler() : hand(&perl_exception) {}

static void osp_unwind_part2(void *vptr)
{
  osp_thr *osp = (osp_thr*) vptr;
#ifndef _OS_CPP_EXCEPTIONS
  osp->hand->hand._unwind_part_2();
#endif
  // this is just a NOP when using C++ exceptions?
  delete osp->hand;
  osp->hand = new dytix_handler();
}

static void ehook(tix_exception_p cause, os_int32 value, os_char_p report)
{
  dOSP;
  DEBUG_txn(warn("before sighandler(SEGV): %s", report));
  osp->report = report;
#ifndef _OS_CPP_EXCEPTIONS
  osp->hand->hand._unwind_part_1(cause, value, report);
#endif
  SAVEDESTRUCTOR(osp_unwind_part2, osp);
  Perl_sighandler(SIGSEGV);
}

/* CCov: on */

#define OSP_THR_SIGNATURE 0x4f535054
dXSTHRINIT(osp, new osp_thr, "ObjStore::ThreadInfo")

osp_thr *osp_thr::fetch()
{
  osp_thr *ret; // =0;
  XSTHRINFO(osp, ret);
  assert(ret);
//  assert(ret->signature == OSP_THR_SIGNATURE);
  return ret;
}

SV *osp_thr::stargate=0;
HV *osp_thr::CLASSLOAD;
SV *osp_thr::TXGV;
AV *osp_thr::TXStack;

void osp_thr::boot()
{
  dSP; 
  int items; 
  XSTHRBOOT(osp);
  tix_exception::set_unhandled_exception_hook(ehook);
  CLASSLOAD = perl_get_hv("ObjStore::CLASSLOAD", 1);
  TXGV = (SV*) gv_stashpv("ObjStore::Transaction", 0);
  assert(TXGV);
  // REFCNT_inc(TXGV) ??
  TXStack = perl_get_av("ObjStore::Transaction::Stack", 1);
//  condpair_magic((SV*) TXStack); //init for later
  SvREADONLY_on(TXStack);
}

osp_thr::osp_thr()
{
  // Fortunately, only Digital UNIX requires this for threads.
  //   (Windows NT & threads unsupported)
  // OS_ESTABLISH_FAULT_HANDLER;

  hand = new dytix_handler();
  signature = OSP_THR_SIGNATURE;
  debug = 0;
  errsv = newSVpv("",0);
  report=0;
}

osp_thr::~osp_thr()
{
  SvREFCNT_dec(errsv);
  // OS_END_FAULT_HANDLER;
}

/*--------------------------------------------- per-transaction context */

osp_txn::osp_txn(os_transaction::transaction_type_enum _tt,
		 os_transaction::transaction_scope_enum scope_in)
  : tt(_tt), ts(scope_in)
{
//  serial = next_txn++;
  os = os_transaction::begin(tt, scope_in);
  ring.next = &ring;
  ring.prev = &ring;

  DEBUG_txn(warn("txn(%p)->new(%s, %s)", this,
		 tt==os_transaction::read_only? "read":
		 tt==os_transaction::update? "update":
		 tt==os_transaction::abort_only? "abort_only":
		 "unknown",
		 ts==os_transaction::local? "local":
		 ts==os_transaction::global? "global":
		 "unknown"));

  SV *myself = sv_setref_pv(newSV(0), "ObjStore::Transaction", this);
  SvREADONLY_on(myself);
  SvREADONLY_on(SvRV(myself));
  SvREADONLY_off(osp_thr::TXStack);
  av_push(osp_thr::TXStack, myself);
  SvREADONLY_on(osp_thr::TXStack);
  assert(this == (osp_txn*) SvIV((SV*) SvRV(myself)));
}

/* CCov:off */
// EXPERIMENTAL
void osp_txn::prepare_to_commit()
{ assert(os); os->prepare_to_commit(); }
int osp_txn::is_prepare_to_commit_invoked()
{ assert(os); return os->is_prepare_to_commit_invoked(); }
int osp_txn::is_prepare_to_commit_completed()
{ assert(os); return os->is_prepare_to_commit_completed(); }
/* CCov:on */

void osp_txn::post_transaction()
{
/* After the transaction is complete, post_transaction() is called
   twice, before the eval unwinds and after. */

  DEBUG_txn(warn("%p->post_transaction", this));

  osp_bridge *br = (osp_bridge*) ring.next;
  while (br != &ring) {
    osp_bridge *next = (osp_bridge*) br->next;
    br->leave_txn();
    br = next;
  }
}

int osp_txn::can_update(os_database *db)
{
  return (os && !os->is_aborted() && tt != os_transaction::read_only && 
	  db && db->is_writable());
}

int osp_txn::can_update(void *vptr)
{
  if (!os || os->is_aborted() || tt == os_transaction::read_only) return 0;
  os_database *db = os_database::of(vptr);
  return db && db->is_writable();
}

int osp_txn::is_aborted()
{
  // returns true after commit XXX?
  return !os || os->is_aborted();
}

void osp_txn::abort()
{
  os_transaction *copy = os;
  os = 0;
  if (!copy) return;
  if (!copy->is_aborted()) {
    DEBUG_txn(warn("txn(%p)->abort", this));
    os_transaction::abort(copy);
  }
  delete copy;
  pop();
}

void osp_txn::commit()
{
  os_transaction *copy = os;
  os = 0;
  if (!copy) return;
  if (!copy->is_aborted()) {
    assert(ring.next == &ring);
    DEBUG_txn(warn("txn(%p)->commit", this));
    os_transaction::commit(copy);
  }
  delete copy;
  pop();
}

void osp_txn::pop()
{
  assert(os==0);
  SvREADONLY_off(osp_thr::TXStack);
  SV *myself = av_pop(osp_thr::TXStack);
  assert(myself != &sv_undef);
  SvREADONLY_on(osp_thr::TXStack);
  assert(sv_isobject(myself) && (SvTYPE(SvRV(myself)) == SVt_PVMG));
  assert(this == (osp_txn*) SvIV((SV*) SvRV(myself)));
  post_transaction();
  SvREFCNT_dec(myself);
}

void osp_txn::checkpoint()
{
  if (!os)
    croak("ObjStore: no transaction to checkpoint");
  if (os->is_aborted())
    croak("ObjStore: cannot checkpoint an aborted transaction");
  assert(ring.next == &ring);
  os_transaction::checkpoint(os);
}

/*--------------------------------------------- osp_bridge */

osp_bridge::osp_bridge()
{
  detached = 0;
  holding = 0;
  manual_hold = 0;
  next = prev = 0;
  refs = 1;
  txsv = 0;

  // get transaction
  if (AvFILL(osp_thr::TXStack) >= 0) {
    SV *txref = *av_fetch(osp_thr::TXStack, AvFILL(osp_thr::TXStack), 0);
    assert(SvROK(txref));
    txsv = SvRV(txref);
    SvREFCNT_inc(txsv);
  }
}

osp_txn *osp_bridge::get_transaction()
{
  assert(txsv);
  osp_txn *txn = (osp_txn*) SvIV(txsv);
  if (!txn) {
    // should be impossible XXX
    warn("array:");
    mysv_dump((SV*)osp_thr::TXStack);
    croak("Transaction null!  Race condition?");
  }
  return txn;
}

void osp_bridge::enter_txn(osp_txn *txn)
{
  mysv_lock(osp_thr::TXGV);
  // should be per-thread
  assert(next==0);
  next = txn->ring.next;
  prev = &txn->ring;
  prev->next = this;
  next->prev = this;
  ++refs;
}

void osp_bridge::leave_perl()
{
  DEBUG_bridge(this, warn("osp_bridge(%p)->leave_perl", this));
  --refs;
  leave_txn();
}
void osp_bridge::leave_txn()
{
  if (!detached) {
    unref();
    if (next) {
      mysv_lock(osp_thr::TXGV);
      // should be per-thread
      --refs;
      next->prev = prev;
      prev->next = next;
      next = prev = 0;
    }
    if (txsv) {
      SvREFCNT_dec(txsv);
      txsv = 0;
    }
    detached=1;
  }
  assert(refs >= 0);
  if (refs == 0) delete this;
}
int osp_bridge::invalid()
{ return detached; }
osp_bridge::~osp_bridge()
{
  DEBUG_bridge(this, warn("bridge(%p)->DESTROY", this));
}

void osp_bridge::hold()
{ croak("bridge::hold()"); }
void osp_bridge::unref()
{ croak("osp_bridge::unref()"); }
int osp_bridge::is_weak()
{ croak("osp_bridge::is_weak()"); return 0; }

