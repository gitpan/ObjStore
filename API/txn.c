#include "osp-preamble.h"
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
  osp_thr *ret;
  XSTHRINFO(osp, ret);
//  assert(ret->signature == OSP_THR_SIGNATURE);
  return ret;
}

SV *osp_thr::stargate=0;
HV *osp_thr::CLASSLOAD;
HV *osp_thr::BridgeStash;
SV *osp_thr::TXGV;
AV *osp_thr::TXStack;

extern "C" XS(boot_ObjStore__CORE);

void osp_thr::boot()
{
  dSP; 
  int items; 
  XSTHRBOOT(osp);
  tix_exception::set_unhandled_exception_hook(ehook);
  CLASSLOAD = perl_get_hv("ObjStore::CLASSLOAD", 1);
  BridgeStash = gv_stashpv("ObjStore::Bridge", 1);
  SvREFCNT_inc((SV*) BridgeStash);
  TXGV = (SV*) gv_stashpv("ObjStore::Transaction", 0);
  assert(TXGV);
  // SvREFCNT_inc(TXGV) ??
  TXStack = perl_get_av("ObjStore::Transaction::Stack", 1);
//  condpair_magic((SV*) TXStack); //init for later
  SvREADONLY_on(TXStack);

  newXS("ObjStore::CORE::boot2", boot_ObjStore__CORE, __FILE__);  // goofy XXX 
}

osp_thr::osp_thr()
  : ospv_freelist(0)
{
  // Fortunately, only Digital UNIX requires this for threads.
  //   (Windows NT & threads unsupported)
  // OS_ESTABLISH_FAULT_HANDLER;

  hand = new dytix_handler();
  signature = OSP_THR_SIGNATURE;
  debug = 0;
  report=0;
}

osp_thr::~osp_thr()
{
  while (!ospv_freelist.empty()) {
    ospv_bridge *br = (ospv_bridge*) ospv_freelist.next->self;
    delete br;
  }
  // OS_END_FAULT_HANDLER;
}

/*--------------------------------------------- per-transaction context */

osp_txn *osp_txn::current()
{
  if (av_len(osp_thr::TXStack) < 0) return 0;
  SV *sv = *av_fetch(osp_thr::TXStack, av_len(osp_thr::TXStack), 0);
  return (osp_txn*) typemap_any::decode(sv);
}

osp_txn::osp_txn(os_transaction::transaction_type_enum _tt,
		 os_transaction::transaction_scope_enum scope_in)
  : tt(_tt), ts(scope_in), link(0)
{
//  serial = next_txn++;
  os = os_transaction::begin(tt, scope_in);

  DEBUG_txn(warn("txn(%p)->new(%s, %s)", this,
		 tt==os_transaction::read_only? "read":
		 tt==os_transaction::update? "update":
		 tt==os_transaction::abort_only? "abort_only":
		 "unknown",
		 ts==os_transaction::local? "local":
		 ts==os_transaction::global? "global":
		 "unknown"));

  SV *myself = osp_thr::any_2sv(this, "ObjStore::Transaction");
  SvREADONLY_off(osp_thr::TXStack);
  av_push(osp_thr::TXStack, myself);
  SvREADONLY_on(osp_thr::TXStack);
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

  osp_bridge *br;
  while (br = (osp_bridge*) link.pop()) {
    br->leave_txn();
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
  // returns true after commit? XXX
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
    assert(link.empty());
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
  assert(myself != &PL_sv_undef);
  SvREADONLY_on(osp_thr::TXStack);
  post_transaction();
  SvREFCNT_dec(myself);
}

void osp_txn::checkpoint()
{
  if (!os)
    croak("ObjStore: no transaction to checkpoint");
  if (os->is_aborted())
    croak("ObjStore: cannot checkpoint an aborted transaction");
  assert(link.empty());
  os_transaction::checkpoint(os);
}

/*--------------------------------------------- osp_bridge */

osp_bridge::osp_bridge()
  : link(this)
{}

void osp_bridge::init(dynacast_fn dcfn)
{
  dynacast = dcfn;
  detached = 0;
  holding = 0;
  manual_hold = 0;
  refs = 1;
  txsv = 0;
}

void osp_bridge::cache_txsv()
{
  assert(av_len(osp_thr::TXStack) >= 0);
  txsv = SvREFCNT_inc(*av_fetch(osp_thr::TXStack,av_len(osp_thr::TXStack), 0));
}

osp_txn *osp_bridge::get_transaction()
{
  assert(txsv);
  osp_txn *txn = (osp_txn*) typemap_any::decode(txsv);
  if (!txn) {
    // should be impossible XXX
    warn("array:");
    Perl_sv_dump((SV*)osp_thr::TXStack);
    croak("Transaction null!  Race condition?");
  }
  return txn;
}

void osp_bridge::enter_txn(osp_txn *txn)
{
  mysv_lock(osp_thr::TXGV);
  // should be per-thread
  assert(link.empty());
  link.attach(&txn->link);
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
    if (!link.empty()) {
      mysv_lock(osp_thr::TXGV);
      // should be per-thread
      --refs;
      link.detach();
    }
    if (txsv) {
      SvREFCNT_dec(txsv);
      txsv = 0;
    }
    detached=1;
  }
  assert(refs >= 0);
  if (refs == 0) freelist();
}
int osp_bridge::invalid()
{ return detached; }
void osp_bridge::freelist() //move to freelist
{ delete this; }
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

