/*
Copyright © 1997-1998 Joshua Nathaniel Pritikin.  All rights reserved.
This package is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.
*/

#include "osperl.h"

/* This is a new API that isn't widely supported yet.  We'll leave it
out by default for now.  Conditional #ifdefs might work too.

double
get_unassigned_address_space()
	CODE:
	RETVAL = objectstore::get_unassigned_address_space(); //64bit? XXX
	OUTPUT:
	RETVAL

*/
/* not yet
void
readonly(sv)
	SV *sv
	PPCODE:
	if (!sv || !SvANY(sv)) XSRETURN_NO;
	if (SvREADONLY(sv)) XSRETURN_YES;
	XSRETURN_NO;
*/

// A few bits of the ObjectStore API are callable outside a
// transaction.  We need to wrap each of these in OSP_START0
// & OSP_END0

static char *private_root_name = "_osperl_private";

// avoid bad spelling
static char *ObjStore_Database = "ObjStore::Database";
static char *ObjStore_Segment = "ObjStore::Segment";

//----------------------------- Constants

static os_fetch_policy str_2fetch(char *str)
{
  if (strEQ(str, "segment")) return os_fetch_segment;
  if (strEQ(str, "page")) return os_fetch_page;
  if (strEQ(str, "stream")) return os_fetch_stream;
  croak("str_2fetch: '%s' unrecognized", str);
}

static objectstore_lock_option str_2lock_option(char *str)
{
  if (strEQ(str, "as_used")) return objectstore::lock_as_used;
  if (strEQ(str, "read")) return objectstore::lock_segment_read;
  if (strEQ(str, "write")) return objectstore::lock_segment_write;
  croak("str_2lock_option: '%s' unrecognized", str);
}

XS(XS_ObjStore_translate)
{ dOSP; perl_call_sv(osp->stargate, G_SCALAR); }

// lookup static symbol (not needed if dynamically linked)
extern "C" XS(boot_ObjStore__REP__ODI);
extern "C" XS(boot_ObjStore__REP__Splash);
extern "C" XS(boot_ObjStore__REP__FatTree);

//----------------------------- ObjStore

MODULE = ObjStore	PACKAGE = ObjStore

BOOT:
  if (items < 3)
    croak("ObjStore::boot(): too few arguments");
  // Nuke the following lines if you are dynamic-linking
  newXS("ObjStore::REP::ODI::bootstrap", boot_ObjStore__REP__ODI, file);
  newXS("ObjStore::REP::Splash::bootstrap", boot_ObjStore__REP__Splash, file);
  newXS("ObjStore::REP::FatTree::bootstrap", boot_ObjStore__REP__FatTree, file);
  //
#ifdef _OS_CPP_EXCEPTIONS
  // Must switch perl to use ANSI C++ exceptions...
  perl_require_pv("ExtUtils::ExCxx");
#endif
  //
  SV* me = perl_get_sv("0", FALSE);  //fetch $0
  assert(me);
  objectstore::set_client_name(SvPV(me, na));
  objectstore::initialize();		// should delay boot for flexibility? XXX
  objectstore::set_auto_open_mode(objectstore::auto_open_disable);
  objectstore::set_incremental_schema_installation(0);    //otherwise is buggy
#ifdef USE_THREADS
  assert(ST(2));
  if (!SvIOK(ST(2)))
    croak("ObjStore::boot(): invalid thread specific key");
  osp_thr::info_key = SvIV(ST(2));
  objectstore::set_thread_locking(1);
  //collections are left without protection...!
#else
  objectstore::set_thread_locking(0);
#endif
  newXSproto("ObjStore::translate", XS_ObjStore_translate, file, "$$");
  HV *szof = perl_get_hv("ObjStore::sizeof", TRUE);
  hv_store(szof, "OSSV", 4, newSViv(sizeof(OSSV)), 0);
  hv_store(szof, "OSPV_iv", 7, newSViv(sizeof(OSPV_iv)), 0);
  hv_store(szof, "OSPV_nv", 7, newSViv(sizeof(OSPV_nv)), 0);
  hv_store(szof, "OSSVPV", 6, newSViv(sizeof(OSSVPV)), 0);
  hv_store(szof, "OSPV_Ref2_hard", 14, newSViv(sizeof(OSPV_Ref2_hard)), 0);
  hv_store(szof, "OSPV_Ref2_protect", 17, newSViv(sizeof(OSPV_Ref2_protect)), 0);

void
reftype(ref)
	SV *ref
	PPCODE:
	if (!SvROK(ref)) XSRETURN_NO;
	ref = SvRV(ref);
	XSRETURN_PV(sv_reftype(ref, 0));

void
blessed(sv)
	SV *sv
	PPCODE:
	if(!sv_isobject(sv))  /*snarfed from builtin:GBARR*/
	  XSRETURN_UNDEF;
	XSRETURN_PV(sv_reftype(SvRV(sv),TRUE));

void
_debug(mask)
	int mask
	PPCODE:
	dOSP ;
	int old = osp->debug;
	osp->debug = mask;
	XSRETURN_IV(old);

void
_tie_objects(yes)
	int yes
	PPCODE:
	dOSP;
	int old = osp->tie_objects;
	osp->tie_objects = yes;
	XSRETURN_IV(old);

SV *
set_stargate(code)
	SV *code
	CODE:
	dOSP ;
	ST(0) = osp->stargate? sv_mortalcopy(osp->stargate):&sv_undef;
	if (!osp->stargate) { osp->stargate = newSVsv(code); }
	else { sv_setsv(osp->stargate, code); }

void
release_name()
	PPCODE:
	XSRETURN_PV((char*) objectstore::release_name());

void
os_version()
	PPCODE:
	// rad perl style version number...
	XSRETURN_NV(objectstore::release_major() + objectstore::release_minor()/100 + objectstore::release_maintenance()/10000);

void
network_servers_available()
	PPCODE:
	XSRETURN_IV(objectstore::network_servers_available());

void
get_page_size()
	PPCODE:
	XSRETURN_IV(objectstore::get_page_size());

os_database *
_lookup(path, mode)
	char *path;
	int mode;
	CODE:
	dOSP;
	char *CLASS = ObjStore_Database;
	OSP_START0
	  RETVAL = os_database::lookup(path, mode);
	  RETVAL->set_check_illegal_pointers(1);
	OSP_ALWAYSEND0
	OUTPUT:
	RETVAL

int
return_all_pages()
	CODE:
	RETVAL = objectstore::return_all_pages();
	OUTPUT:
	RETVAL

void
get_all_servers()
	PPCODE:
	char *CLASS = "ObjStore::Server";
	os_int32 num = objectstore::get_n_servers();
	if (num == 0) XSRETURN_EMPTY;
	os_server_p *svrs = new os_server_p[num];
	objectstore::get_all_servers(num, svrs, num);
	EXTEND(sp, num);
	int xx;
	for (xx=0; xx < num; xx++) {
		PUSHs(sv_setref_pv(sv_newmortal(), CLASS, svrs[xx] ));
	}
	delete [] svrs;

#-----------------------------# Notification

MODULE = ObjStore	PACKAGE = ObjStore

void
subscribe(...)
	PPCODE:
	PUTBACK;
	if (items == 0) return;
	os_subscription *subs = new os_subscription[items];
	dOSP;
	for (int xa=0; xa < items; xa++) {
	  ospv_bridge *br = osp->sv_2bridge(ST(xa), 1);
	  subs[xa].assign(br->ospv());
	}
	OSP_START0
	  os_notification::subscribe(subs, items);
	OSP_ALWAYS0
	  delete [] subs;
	OSP_END0
	return;

void
unsubscribe(...)
	PPCODE:
	PUTBACK;
	if (items == 0) return;
	os_subscription *subs = new os_subscription[items];
	dOSP;
	for (int xa=0; xa < items; xa++) {
	  ospv_bridge *br = osp->sv_2bridge(ST(xa), 1);
	  subs[xa].assign(br->ospv());
	}
	OSP_START0
	  os_notification::unsubscribe(subs, items);
	OSP_ALWAYS0
	  delete [] subs;
	OSP_END0
	return;

MODULE = ObjStore	PACKAGE = ObjStore::Notification

static void
os_notification::set_queue_size(size)
	int size;

static void
os_notification::queue_status()
	PPCODE:
	os_unsigned_int32 sz, pend, over;
	os_notification::queue_status(sz, pend, over);
	EXTEND(SP, 3);
	PUSHs(sv_2mortal(newSViv(sz)));
	PUSHs(sv_2mortal(newSViv(pend)));
	PUSHs(sv_2mortal(newSViv(over)));

static int
os_notification::_get_fd()

static void
os_notification::receive(...)
	PROTOTYPE: $;$
	PPCODE:
	os_int32 timeout = -1;
	if (items > 1) timeout = SvNV(ST(1)) * 1000;
	os_notification *note;
	if (os_notification::receive(note, timeout)) {
	  XPUSHs(sv_setref_pv(sv_newmortal(), "ObjStore::Notification", note));
	} else {
	  XPUSHs(&sv_undef);
	}

void
os_notification::_get_database()
	PPCODE:
	XPUSHs(sv_setref_pv(sv_newmortal(), "ObjStore::Database",
	  THIS->get_database()));

void
os_notification::focus()
	PPCODE:
	PUTBACK;
	dOSP;
	SV *ret;
	ret = osp->ospv_2sv((OSSVPV *) THIS->get_reference().resolve());
	SPAGAIN;
	XPUSHs(ret);

void
os_notification::why()
	PPCODE:
	char *str = (char*) THIS->get_string();
	assert(str);
	if (str[0] == 0) {
	  XPUSHs(sv_2mortal(newSViv(THIS->get_kind())));
	} else {
	  XPUSHs(sv_2mortal(newSVpv(str, 0)));
	}

void
os_notification::DESTROY()

MODULE = ObjStore	PACKAGE = ObjStore::UNIVERSAL

void
OSSVPV::notify(why, ...)
	SV *why
	PROTOTYPE: $$;$
	CODE:
	int now=0;
	if (items == 3) {
	  if (SvPOK(ST(2)) && strEQ(SvPV(ST(2), na), "now")) now=1;
	  else croak("%p->notify('%s', ['now'])", THIS, SvPV(why, na));
	}
	os_notification note;
	if (SvNIOK(why)) {
	  os_int32 kind = SvIV(why);
	  if (kind < 0)
	    croak("%p->notify(%d): non-positive numbers are reserved", kind);
	  note.assign(THIS, kind, 0);
	} else {
	  note.assign(THIS, 0, SvPV(why, na));
	}
	OSP_START0
	  if (now) os_notification::notify_immediate(&note, 1);
	  else     os_notification::notify_on_commit(&note, 1);
	OSP_ALWAYSEND0

#-----------------------------# Transaction

# It is not clear why perl should need access to any transaction that
# is not the most deeply nested...

MODULE = ObjStore	PACKAGE = ObjStore::Transaction

osp_txn *
new(how)
	char *how
	CODE:
	char *CLASS = "ObjStore::Transaction";
	os_transaction::transaction_type_enum tt;
	if (strEQ(how, "read")) tt = os_transaction::read_only;
	else if (strEQ(how, "update")) tt = os_transaction::update;
	else if (strEQ(how, "abort_only") ||
	         strEQ(how, "abort")) tt = os_transaction::abort_only;
	else croak("ObjStore::begin(%s): unknown transaction type", how);
	RETVAL = new osp_txn(tt, os_transaction::local);
	OUTPUT:
	RETVAL

void
osp_txn::destroy()
	CODE:
	delete THIS;	//must be precise about when this happens

void
osp_txn::deadlocked()
	PPCODE:
	XSRETURN_IV(THIS->deadlocked);

void
osp_txn::top_level()
	PPCODE:
	XSRETURN_IV(THIS->up == 0);

void
osp_txn::abort()

void
osp_txn::commit()

char *
SEGV_reason()
	PPCODE:
	dOSP ; dTXN ;
	if (!txn || !txn->report) XSRETURN_UNDEF;
	XSRETURN_PV(txn->report);

void
osp_txn::post_transaction()

osp_txn *
get_current()
	CODE:
	char *CLASS = "ObjStore::Transaction";
	dOSP ; dTXN ;
	RETVAL = txn;
	OUTPUT:
	RETVAL

void
osp_txn::get_type()
	PPCODE:
	switch (THIS->tt) {
	case os_transaction::abort_only: XSRETURN_PV("abort_only");
	case os_transaction::read_only: XSRETURN_PV("read");
	case os_transaction::update: XSRETURN_PV("update");
	}
	croak("os_transaction::get_type(): unknown transaction type");

void
osp_txn::prepare_to_commit()
	CODE:
	warn("prepare_to_commit() is experimental");
	THIS->prepare_to_commit();

int
osp_txn::is_prepare_to_commit_invoked()

int
osp_txn::is_prepare_to_commit_completed()

MODULE = ObjStore	PACKAGE = ObjStore

void
_set_transaction_priority(pri)
	int pri;
	CODE:
	objectstore::set_transaction_priority(pri);

int
is_lock_contention()
	CODE:
	RETVAL = objectstore::is_lock_contention();
	OUTPUT:
	RETVAL

char *
get_lock_status(ospv)
	OSSVPV *ospv
	CODE:
	int st;
	st = objectstore::get_lock_status(ospv);
	switch (st) {
	case os_read_lock: RETVAL = "read"; break;
	case os_write_lock: RETVAL = "write"; break;
	default: XSRETURN_NO;
	}
	OUTPUT:
	RETVAL

int
get_readlock_timeout()
	CODE:
	RETVAL = objectstore::get_readlock_timeout();
	OUTPUT:
	RETVAL

int
get_writelock_timeout()
	CODE:
	RETVAL = objectstore::get_writelock_timeout();
	OUTPUT:
	RETVAL

void
set_readlock_timeout(tm)
	int tm;
	CODE:
	objectstore::set_readlock_timeout(tm);

void
set_writelock_timeout(tm)
	int tm;
	CODE:
	objectstore::set_writelock_timeout(tm);

#-----------------------------# Server

MODULE = ObjStore	PACKAGE = ObjStore::Server

char *
os_server::get_host_name()

int
os_server::connection_is_broken()

void
os_server::disconnect()

void
os_server::reconnect()

void
os_server::get_databases()
	PPCODE:
	char *CLASS = ObjStore_Database;
	os_int32 num = THIS->get_n_databases();
	assert(num > 0);  //?
	os_database_p *dbs = new os_database_p[num];
	THIS->get_databases(num, dbs, num);
	EXTEND(sp, num);
	int xx;
	for (xx=0; xx < num; xx++) {
		PUSHs(sv_setref_pv(sv_newmortal(), CLASS, dbs[xx] ));
	}
	delete [] dbs;

#-----------------------------# Database

MODULE = ObjStore	PACKAGE = ObjStore

int
get_n_databases()
	CODE:
	RETVAL = os_database::get_n_databases();
	OUTPUT:
	RETVAL

MODULE = ObjStore	PACKAGE = ObjStore::Database

void
os_database::_open(read_only)
	int read_only
	PPCODE:
	dOSP;
	OSP_START0
	  THIS->open(read_only);
	OSP_ALWAYSEND0
	XSRETURN_YES;

void
os_database::_open_mvcc()
	PPCODE:
	dOSP;
	OSP_START0
	  THIS->open_mvcc();
	OSP_ALWAYSEND0
	XSRETURN_YES;

void
os_database::close()

void
os_database::_destroy()
	CODE:
	THIS->destroy();

void
os_database::get_host_name()
	PPCODE:
	char *path = THIS->get_host_name();
	XPUSHs(sv_2mortal(newSVpv(path, 0)));
	delete path;

void
os_database::get_pathname()
	PPCODE:
	char *path = THIS->get_pathname();
	XPUSHs(sv_2mortal(newSVpv(path, 0)));
	delete path;

void
os_database::get_relative_directory()
	PPCODE:
	char *path = THIS->get_relative_directory();
	if (!path) XSRETURN_UNDEF;
	XPUSHs(sv_2mortal(newSVpv(path, 0)));
	delete path;

void
os_database::get_id(...)
	PPCODE:
	os_database_id *id = THIS->get_id();
	XPUSHs(sv_2mortal(newSVpvf("%08p%08p%08p",id->word0,id->word1,id->word2)));

int
os_database::get_default_segment_size()

int
os_database::get_sector_size()

int
os_database::size()

int
os_database::size_in_sectors()

time_t
os_database::time_created()

char *
os_database::is_open()
	CODE:
	if (THIS->is_open_mvcc()) RETVAL = "mvcc";
	else if (THIS->is_open_read_only()) RETVAL = "read";
	else if (THIS->is_open()) RETVAL = "update";
	else RETVAL = "";
	OUTPUT:
	RETVAL

void
os_database::is_writable()
	PPCODE:
	// not ODI spec; but more useful
	if (THIS->is_open_read_only()) XSRETURN_NO;
	dOSP; dTXN;
	if (txn && txn->tt == os_transaction::read_only) XSRETURN_NO;
	XSRETURN_YES;

void
os_database::set_fetch_policy(policy, ...)
	char *policy;
	PROTOTYPE: $;$
	CODE:
	int bytes=4096;
	if (items == 3) bytes = SvIV(ST(2));
	else if (items > 3) croak("os_database::set_fetch_policy(policy, [sz])");
	THIS->set_fetch_policy(str_2fetch(policy), bytes);

void
os_database::set_lock_whole_segment(policy)
	char *policy;
	CODE:
	THIS->set_lock_whole_segment(str_2lock_option(policy));

os_segment *
os_database::get_default_segment()
	CODE:
	char *CLASS = ObjStore_Segment;
	RETVAL = THIS->get_default_segment();
	OUTPUT:
	RETVAL

os_segment *
os_database::get_segment(num)
	int num
	CODE:
	char *CLASS = ObjStore_Segment;
	RETVAL = THIS->get_segment(num);
	OUTPUT:
	RETVAL

void
os_database::get_all_segments()
	PPCODE:
	char *CLASS = ObjStore_Segment;
	os_int32 num = THIS->get_n_segments();
	assert(num > 0); //?ok
	os_segment_p *segs = new os_segment_p[num];
	THIS->get_all_segments(num, segs, num);
	EXTEND(sp, num);
	int xx;
	for (xx=0; xx < num; xx++) {
		PUSHs(sv_setref_pv(sv_newmortal(), CLASS, segs[xx] ));
	}
	delete [] segs;

void
os_database::_PRIVATE_ROOT()
	PPCODE:
	dOSP;
	dTXN;
	os_database_root *rt = THIS->find_root(private_root_name);
	if (!rt && txn && txn->can_update(THIS)) {
	  rt = THIS->create_root(private_root_name);
	  rt->set_value(0, OSSV::get_os_typespec());
	}
	if (rt) XPUSHs(sv_setref_pv(sv_newmortal(), "ObjStore::Root", rt));
	else    XPUSHs(&sv_undef);

void
os_database::get_all_roots()
	PPCODE:
	char *CLASS = "ObjStore::Root";
	os_int32 num = THIS->get_n_roots();
	if (num == 0) XSRETURN_EMPTY;
	os_database_root_p *roots = new os_database_root_p[num];
	THIS->get_all_roots(num, roots, num);
	for (int xx=0; xx < num; xx++) {
	  assert(roots[xx]);
	  char *nm = roots[xx]->get_name();
	  int priv = strEQ(nm, private_root_name);
	  if (!priv) XPUSHs(sv_setref_pv(sv_newmortal(), CLASS, roots[xx] ));
	}
	delete [] roots;

#-----------------------------# Root

MODULE = ObjStore	PACKAGE = ObjStore::Database

os_database_root *
os_database::create_root(name)
	char *name
	PREINIT:
	char *CLASS = "ObjStore::Root";
	CODE:
	DEBUG_root(warn("%p->create_root(%s)", THIS, name));
	RETVAL = THIS->create_root(name);
	assert(RETVAL);
	RETVAL->set_value(0, OSSV::get_os_typespec());
	OUTPUT:
	RETVAL

os_database_root *
os_database::find_root(name)
	char *name
	PREINIT:
	char *CLASS = "ObjStore::Root";
	CODE:
	if (strEQ(name, private_root_name)) XSRETURN_UNDEF; //force awareness
	DEBUG_root(warn("%p->find_root(%s)", THIS, name));
	RETVAL = THIS->find_root(name);
	DEBUG_root(warn("%p->find_root(%s) = %p", THIS, name, RETVAL));
	OUTPUT:
	RETVAL

MODULE = ObjStore	PACKAGE = ObjStore::Root

void
os_database_root::destroy()
	CODE:
	DEBUG_root(warn("%p->destroy_root()", THIS));
	OSSV *old = (OSSV*) THIS->get_value();
	if (old) delete old;
	delete THIS;

char *
os_database_root::get_name()

void
os_database_root::get_value()
	PPCODE:
	PUTBACK ;
	OSSV *ossv = (OSSV*) THIS->get_value(OSSV::get_os_typespec());
	DEBUG_root(warn("%p->get_value() = OSSV=%p", THIS, ossv));
	dOSP ;
	SV *ret;
	ret = osp->ossv_2sv(ossv);
	SPAGAIN ;
	XPUSHs(ret);

void
os_database_root::set_value(sv)
	SV *sv
	PPCODE:
	PUTBACK ;
	dOSP ;
	os_segment *WHERE = os_database::of(THIS)->get_default_segment();
	OSSVPV *pv=0;
	ospv_bridge *br = osp->sv_2bridge(sv, 1, WHERE);
	pv = br->ospv();
	// Disallow scalars in roots because it is fairly useless and messy.
	OSSV *ossv = (OSSV*) THIS->get_value(OSSV::get_os_typespec());
	if (ossv) {
	  DEBUG_root(warn("%p->set_value(): OSSV(%p)=%p", THIS, ossv, pv));
	  ossv->s(pv);
	} else {
	  DEBUG_root(warn("%p->set_value(): planting %p", THIS, pv));
	  ossv = osp->plant_ospv(WHERE, pv);
	  THIS->set_value(ossv, OSSV::get_os_typespec());
	}
	return;

#-----------------------------# Segment

MODULE = ObjStore	PACKAGE = ObjStore::Database

os_segment *
os_database::_create_segment()
	PREINIT:
	char *CLASS = ObjStore_Segment;
	CODE:
	RETVAL = THIS->create_segment();
	OUTPUT:
	RETVAL

MODULE = ObjStore	PACKAGE = ObjStore::Segment

os_segment *
get_transient_segment()
	CODE:
	char *CLASS = ObjStore_Segment;
	RETVAL = os_segment::get_transient_segment();
	OUTPUT:
	RETVAL

void
os_segment::_destroy()
	CODE:
	THIS->destroy();

int
os_segment::is_empty()

int
os_segment::is_deleted()

int
os_segment::return_memory(now)
	int now

int
os_segment::size()

int
os_segment::set_size(new_sz)
	int new_sz

int
os_segment::unused_space()

int
os_segment::get_number()

void
os_segment::set_comment(info)
	char *info
	CODE:
	char short_info[32];
	strncpy(short_info, info, 31);
	short_info[31] = 0;
	THIS->set_comment(short_info);

void
os_segment::get_comment()
	PPCODE:
	char *cm = THIS->get_comment();
	XPUSHs(sv_2mortal(newSVpv(cm, 0)));
	delete cm;

void
os_segment::lock_into_cache()

void
os_segment::unlock_from_cache()

void
os_segment::set_fetch_policy(policy, ...)
	char *policy;
	PROTOTYPE: $;$
	CODE:
	int bytes=4096;
	if (items == 3) bytes = SvIV(ST(2));
	else if (items > 3) croak("os_database::set_fetch_policy(policy, [sz])");
	THIS->set_fetch_policy(str_2fetch(policy), bytes);

void
os_segment::set_lock_whole_segment(policy)
	char *policy;
	CODE:
	THIS->set_lock_whole_segment(str_2lock_option(policy));

os_database *
os_segment::_database_of()
	PREINIT:
	char *CLASS = ObjStore_Database;
	CODE:
	RETVAL = THIS->database_of();
	OUTPUT:
	RETVAL

#-----------------------------# Bridge

MODULE = ObjStore	PACKAGE = ObjStore::Bridge

void
osp_bridge::DESTROY()
	CODE:
	DEBUG_bridge(warn("osp_bridge(%p)->release", THIS));
	THIS->release();

#-----------------------------# UNIVERSAL

MODULE = ObjStore	PACKAGE = ObjStore::UNIVERSAL

int
_is_persistent(sv)
	SV *sv;
	CODE:
	dOSP;
	ospv_bridge *br = osp->sv_2bridge(sv, 0);
	RETVAL = br != 0;
	OUTPUT:
	RETVAL

void
_pstringify(THIS, ...)
	SV *THIS;
	PROTOTYPE: $;$$
	PPCODE:
	dOSP;
	ospv_bridge *br = osp->sv_2bridge(THIS, 0);
	SV *ret;
	if (!br) {
	  STRLEN len;
	  int amagic = SvAMAGIC(THIS);  // concurrency problem? XXX
	  SvAMAGIC_off(THIS);
	  char *str = sv_2pv(THIS, &len);
	  if (amagic) SvAMAGIC_on(THIS);
	  assert(str);
	  ret = newSVpv(str, len);
	} else {
	  char *rtype = sv_reftype(THIS, 0);
	  //just read the stash? XXX
	  STRLEN CLEN;
	  char *CLASS = br->ospv()->blessed_to(&CLEN);
	  ret = newSVpvf("%s=%s(0x%p)",CLASS,rtype,br->ospv());
	}
	XPUSHs(sv_2mortal(ret));

int
_peq(a1, a2, ign)
	SV *a1
	SV *a2
	SV *ign
	CODE:
	dOSP;
	ospv_bridge *b1 = osp->sv_2bridge(a1, 0);
	ospv_bridge *b2 = osp->sv_2bridge(a2, 0);
	RETVAL = b1 && b2 && b1->ospv() == b2->ospv();
	OUTPUT:
	RETVAL

int
_pneq(a1, a2, ign)
	SV *a1
	SV *a2
	SV *ign
	CODE:
	dOSP;
	ospv_bridge *b1 = osp->sv_2bridge(a1, 0);
	ospv_bridge *b2 = osp->sv_2bridge(a2, 0);
	RETVAL = !b1 || !b2 || b1->ospv() != b2->ospv();
	OUTPUT:
	RETVAL

void
OSSVPV::_refcnt()
	PPCODE:
	XPUSHs(sv_2mortal(newSViv(THIS->_refs)));

void
OSSVPV::_rocnt()
	PPCODE:
	XPUSHs(sv_2mortal(newSViv(OSPvROCNT(THIS))));

void
OSSVPV::_blessto_slot(...)
	PROTOTYPE: ;$
	PPCODE:
	PUTBACK;
	if (items == 2) {
	  ospv_bridge *br = osp->sv_2bridge(ST(1), 1);
	  OSSVPV *nval = (OSSVPV*) br->ospv();
	  nval->REF_inc();
	  if (OSPvBLESS2(THIS) && THIS->classname)
	    ((OSSVPV*)THIS->classname)->REF_dec();
	  OSPvBLESS2_on(THIS);
	  THIS->classname = (char*)nval;
	}
	if (!(!OSPvBLESS2(THIS) || GIMME_V == G_VOID)) {
	  SV *ret = osp->ospv_2sv((OSSVPV*)THIS->classname);
	  SPAGAIN;
	  XPUSHs(ret);
	  PUTBACK;
	}
	return;

os_database *
OSSVPV::_database_of()
	CODE:
	char *CLASS = ObjStore_Database;
	RETVAL = os_database::of(THIS);
	OUTPUT:
	RETVAL

os_segment *
OSSVPV::segment_of()
	CODE:
	char *CLASS = ObjStore_Segment;
	RETVAL = os_segment::of(THIS);
	OUTPUT:
	RETVAL

void
OSSVPV::os_class()
	PPCODE:
	STRLEN len;
	char *str = THIS->os_class(&len);
	XPUSHs(sv_2mortal(newSVpv(str, len)));

void
OSSVPV::rep_class()
	PPCODE:
	STRLEN len;
	char *str = THIS->rep_class(&len);
	XPUSHs(sv_2mortal(newSVpv(str, len)));

void
OSSVPV::get_pointer_numbers()
	PPCODE:
	os_unsigned_int32 n1,n2,n3;
	objectstore::get_pointer_numbers(THIS, n1, n2, n3);
	XPUSHs(sv_2mortal(newSVpvf("%08p%08p", n1, n3)));

void
OSSVPV::const()
	PPCODE:
	OSPvROCNT(THIS) = ~0;
	THIS->XSHARE(1);

void
OSSVPV::POSH_CD(keyish)
	char *keyish
	PPCODE:
	PUTBACK;
	STRLEN len;
	OSSV *sv = THIS->traverse(keyish);
	if (!sv) croak("OSSVPV(%p=%s)->traverse('%s') failed", 
			THIS, THIS->os_class(&len), keyish);
	SV *ret = osp->ossv_2sv(sv);
	SPAGAIN;
	XPUSHs(ret);

void
OSSVPV::_new_ref(type, sv1)
	int type;
	SV *sv1;
	PPCODE:
	PUTBACK;
	os_segment *seg = osp->sv_2segment(sv1);
	SV *ret;
	if (type == 0) {
	  ret = osp->ospv_2sv(new (seg, OSPV_Ref2_protect::get_os_typespec())
		OSPV_Ref2_protect(THIS));
	} else if (type == 1) {
	  ret = osp->ospv_2sv(new (seg, OSPV_Ref2_hard::get_os_typespec())
		OSPV_Ref2_hard(THIS));
	} else { croak("OSSVPV->new_ref(): unknown type"); }
	SPAGAIN;
	XPUSHs(ret);

#-----------------------------# Container

MODULE = ObjStore	PACKAGE = ObjStore::Container

double
OSPV_Container::_percent_filled()
	CODE:
	warn("_percent_filled is experimental");
	RETVAL = THIS->_percent_filled();
	if (RETVAL < 0 || RETVAL > 1) XSRETURN_UNDEF;
	OUTPUT:
	RETVAL

int
OSPV_Generic::_count()

void
OSPV_Container::_new_cursor(sv1)
	SV *sv1;
	PPCODE:
	PUTBACK;
	os_segment *seg = osp->sv_2segment(sv1);
	SV *ret = osp->ospv_2sv(THIS->new_cursor(seg));
	SPAGAIN;
	XPUSHs(ret);

#-----------------------------# AV

MODULE = ObjStore	PACKAGE = ObjStore::AV

void
OSPV_Generic::FETCH(xx)
	SV *xx;
	PPCODE:
	SV **savesp = SP;
	PUTBACK;
	SV *ret = osp->ossv_2sv(THIS->FETCH(xx));
	SPAGAIN;
	assert(SP == savesp);
	XPUSHs(ret);

void
OSPV_Generic::STORE(xx, nval)
	SV *xx;
	SV *nval;
	PPCODE:
	SV **savesp = SP;
	PUTBACK;
	SV *ret = osp->ossv_2sv(THIS->STORE(xx, nval));
	SPAGAIN;
	assert(SP == savesp);
	if (ret) XPUSHs(ret);

void
OSPV_Generic::CLEAR()

void
OSPV_Generic::_Pop()
	PPCODE:
	PUTBACK;
	SV *ret = THIS->Pop();
	SPAGAIN;
	if (ret) XPUSHs(ret);

void
OSPV_Generic::_Push(nval)
	SV *nval;
	CODE:
	THIS->Push(nval);

#-----------------------------# HV

MODULE = ObjStore	PACKAGE = ObjStore::HV

void
OSPV_Generic::FETCH(key)
	SV *key;
	PPCODE:
	SV **savesp = SP;
	PUTBACK;
	SV *ret = osp->ossv_2sv(THIS->FETCH(key));
	SPAGAIN;
	assert(SP == savesp);
	if (ret) XPUSHs(ret);

void
OSPV_Generic::STORE(key, nval)
	SV *key;
	SV *nval;
	PPCODE:
	SV **savesp = SP;
	PUTBACK;
	SV *ret = osp->ossv_2sv(THIS->STORE(key, nval));
	SPAGAIN;
	assert(SP == savesp);
	if (ret) XPUSHs(ret);

void
OSPV_Generic::DELETE(key)
	char *key
	CODE:
	// returns deleted? maybe stack could change? XXX
	THIS->DELETE(key);

int
OSPV_Generic::EXISTS(key)
	char *key

void
OSPV_Generic::FIRSTKEY()
	PPCODE:
	PUTBACK;
	SV *ret = THIS->FIRST( THIS_bridge );
	SPAGAIN;
	XPUSHs(ret);

void
OSPV_Generic::NEXTKEY(...)
	PPCODE:
	if (items > 2) croak("NEXTKEY: too many arguments");
	PUTBACK;
	SV *ret = THIS->NEXT( THIS_bridge );
	SPAGAIN;
	XPUSHs(ret);

void
OSPV_Generic::CLEAR()

#-----------------------------# Index

MODULE = ObjStore	PACKAGE = ObjStore::Index

void
OSPV_Generic::add(sv)
	SV *sv;
	PPCODE:
	PUTBACK;
	ospv_bridge *br = osp->sv_2bridge(sv, 1, os_segment::of(THIS));
	THIS->add(br->ospv());
	SPAGAIN;
	if (GIMME_V != G_VOID) PUSHs(sv);

void
OSPV_Generic::remove(sv)
	SV *sv
	PPCODE:
	PUTBACK;
	ospv_bridge *br = osp->sv_2bridge(sv, 1);
	THIS->remove(br->ospv());
	return;

void
OSPV_Generic::configure(...)
	PPCODE:
	SV **top = &ST(0);
	PUTBACK;
	THIS->configure(top, items);
	return;

void
OSPV_Generic::FETCH(keyish)
	SV *keyish
	PPCODE:
	PUTBACK;
	SV *ret = osp->ospv_2sv(THIS->FETCHx(keyish));
	SPAGAIN;
	XPUSHs(ret);

void
OSPV_Generic::CLEAR()

#-----------------------------# Ref

MODULE = ObjStore	PACKAGE = ObjStore::Ref

os_database *
OSPV_Ref2::_get_database()
	PREINIT:
	char *CLASS = ObjStore_Database;
	CODE:				//should be just like lookup
	OSP_START0
	  RETVAL = THIS->get_database();
	  RETVAL->set_check_illegal_pointers(1);
	OSP_ALWAYSEND0
	OUTPUT:
	RETVAL

void
OSPV_Ref2::dump()
	PPCODE:
	char *str = THIS->dump();
	XPUSHs(sv_2mortal(newSVpv(str,0)));
	delete str;

int
OSPV_Ref2::deleted()

void
OSPV_Ref2::focus()
	PPCODE:
	PUTBACK;
	SV *sv = osp->ospv_2sv(THIS->focus());
	SPAGAIN;
	XPUSHs(sv);

void
_load(CLASS, sv1, type, dump, db)
	SV *CLASS;
	SV *sv1;
	int type;
	char *dump;
	os_database *db;
	PPCODE:
	PUTBACK;
	dOSP;
	os_segment *seg = osp->sv_2segment(sv1);
	OSPV_Ref2 *ref;
	if (type == 0) {
	  ref = new (seg, OSPV_Ref2_protect::get_os_typespec())
			OSPV_Ref2_protect(dump, db);
	} else if (type == 1) {
	  ref = new (seg, OSPV_Ref2_hard::get_os_typespec())
			OSPV_Ref2_hard(dump, db);
	} else { croak("OSSVPV->_load(): unknown type"); }
	ref->bless(CLASS);
	return;

#-----------------------------# Cursor

MODULE = ObjStore	PACKAGE = ObjStore::Cursor

void
OSPV_Cursor2::focus()
	PPCODE:
	PUTBACK;
	SV *sv = osp->ospv_2sv(THIS->focus());
	SPAGAIN;
	XPUSHs(sv);

void
OSPV_Cursor2::moveto(where)
	int where

void
OSPV_Cursor2::step(delta)
	int delta
	PPCODE:
	PUTBACK;
	THIS->step(delta);
	return;

void
OSPV_Cursor2::each(...)
	PROTOTYPE: ;$
	PPCODE:
	int delta = 1;
	if (items == 2) {
	  if (!SvIOK(ST(1))) croak("each takes an integer step size");
	  delta = SvIV(ST(1));
	}
	PUTBACK;
	THIS->step(delta);
	THIS->at();
	return;

void
OSPV_Cursor2::at()
	PPCODE:
	PUTBACK;
	THIS->at();
	return;

void
OSPV_Cursor2::store(nval)
	SV *nval
	PPCODE:
	PUTBACK;
	THIS->store(nval);
	return;

void
OSPV_Cursor2::seek(...)
	PPCODE:
	SV **top = &ST(0);
	PUTBACK;
	int ret = THIS->seek(top, items);
	SPAGAIN;
	XPUSHs(sv_2mortal(newSViv(ret)));

int
OSPV_Cursor2::pos()

void
OSPV_Cursor2::keys()
	PPCODE:
	PUTBACK;
	THIS->keys();
	return;

#-----------------------------# Set - DEPRECIATED!!

MODULE = ObjStore	PACKAGE = ObjStore::Set

void
OSPV_Generic::add(...)
	CODE:
	for (int xx=1; xx < items; xx++) THIS->set_add(ST(xx));

int
OSPV_Generic::contains(val)
	SV *val;
	CODE:
	THIS->set_contains(val);

void
OSPV_Generic::rm(nval)
	SV *nval
	CODE:
	THIS->set_rm(nval);

SV *
OSPV_Generic::first()
	CODE:
	ST(0) = THIS->FIRST( THIS_bridge );  //buggy

SV *
OSPV_Generic::next()
	CODE:
	ST(0) = THIS->NEXT( THIS_bridge );  //buggy

#-----------------------------# Cursor

MODULE = ObjStore	PACKAGE = ObjStore::DEPRECIATED::Cursor

void
OSPV_Cursor::moveto(side)
	SV *side
	CODE:
	if (SvPOKp(side)) {
	  char *str = SvPV(side, na);
	  if (strEQ(str, "end")) THIS->seek_pole(1);
	  else warn("%p->moveto(%s): undefined", THIS, str);
	} else if (SvIOK(side)) {
	  if (SvIV(side)==0 || SvIV(side)==-1) THIS->seek_pole(0);
	  else warn("%p->moveto(%d): unsupported", THIS, SvIV(side));
	} else croak("moveto");

void
OSPV_Cursor::at()
	PPCODE:
	PUTBACK; THIS->at(); return;

void
OSPV_Cursor::next()
	PPCODE:
	PUTBACK; THIS->next(); return;

#-----------------------------# Ref

MODULE = ObjStore	PACKAGE = ObjStore::DEPRECIATED::Ref

os_database *
OSPV_Ref::get_database()
	PREINIT:
	char *CLASS = ObjStore_Database;

int
OSPV_Ref::deleted()

void
OSPV_Ref::focus()
	PPCODE:
	PUTBACK;
	SV *sv = osp->ospv_2sv(THIS->focus());
	SPAGAIN;
	XPUSHs(sv);

MODULE = ObjStore	PACKAGE = ObjStore

void
release_major()
	PPCODE:
	warn("release_major() is depreciated; try os_version instead");
	XSRETURN_IV(objectstore::release_major());


void
release_minor()
	PPCODE:
	warn("release_minor() is depreciated; try os_version instead");
	XSRETURN_IV(objectstore::release_minor());

void
release_maintenance()
	PPCODE:
	warn("release_maintenance() is depreciated; try os_version instead");
	XSRETURN_IV(objectstore::release_maintenance());

MODULE = ObjStore	PACKAGE = ObjStore::Database

void
os_database::_allow_external_pointers(yes)
	int yes
	CODE:
	// DO NOT USE THIS!
	THIS->allow_external_pointers(yes);
	// WARNING WARNING

#-----------------------------# Segment Cursor

MODULE = ObjStore	PACKAGE = ObjStore::Segment

os_object_cursor *
os_segment::new_cursor()
	CODE:
	char *CLASS = "ObjStore::Segment::Cursor";
	RETVAL = new os_object_cursor(THIS);
	OUTPUT:
	RETVAL

MODULE = ObjStore	PACKAGE = ObjStore::Segment::Cursor

void
os_object_cursor::current(sz)
	int sz;
	PPCODE:
	void *ptr;
	const os_type *ty;
	os_int32 count;
	if (!THIS->current(ptr, ty, count)) XSRETURN_UNDEF;
	XPUSHs(sv_2mortal(newSVpv((char*)ptr, count * sz)));

void
os_object_cursor::first()

void
os_object_cursor::next()

int
os_object_cursor::more()

void
os_object_cursor::DESTROY()

