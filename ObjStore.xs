/*
Copyright (c) 1997 Joshua Nathaniel Pritikin.  All rights reserved.
This package is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.
*/

#include "osperl.h"

// A few bits of the ObjectStore API are callable outside a
// transaction.  We need to wrap each of these in TIX_HANDLE
// and convert TIX exceptions into perl exceptions using:

#define CAPTURE_TIX_REPORT \
	  sv_setpv(osp->errsv, tix_local_handler.get_report()); \
	  STRLEN len; \
	  char *str = SvPV(osp->errsv, len); \
	  if (str && len) str[len-1] = 0;

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
  croak("str_2fetch: %s unrecognized", str);
}

static objectstore_lock_option str_2lock_option(char *str)
{
  if (strEQ(str, "as_used")) return objectstore::lock_as_used;
  if (strEQ(str, "read")) return objectstore::lock_segment_read;
  if (strEQ(str, "write")) return objectstore::lock_segment_write;
  croak("str_2lock_option: %s unrecognized", str);
}

XS(XS_ObjStore_translate)
{ dOSP ; perl_call_sv(osp->stargate, G_SCALAR); }

// lookup static symbol (not needed if dynamically linked)
extern "C" XS(boot_ObjStore__GENERIC);

//----------------------------- ObjStore

MODULE = ObjStore	PACKAGE = ObjStore

BOOT:
  if (items < 3)
    croak("ObjStore::boot(): too few arguments");
  // Nuke the following line if you are dynamic-linking ObjStore::GENERIC
  newXS("ObjStore::GENERIC::bootstrap", boot_ObjStore__GENERIC, file);
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

SV *
reftype(ref)
	SV *ref
	CODE:
	if (!SvROK(ref)) XSRETURN_NO;
	ref = SvRV(ref);
	XSRETURN_PV(sv_reftype(ref, 0));

char *
blessed(sv)
	SV *sv
	CODE:
{
    if(!sv_isobject(sv)) {
        XSRETURN_UNDEF;
    }
    RETVAL = sv_reftype(SvRV(sv),TRUE);
}
OUTPUT:
	RETVAL

int
_debug(mask)
	int mask
	CODE:
	dOSP ;
	RETVAL = osp->debug;
	osp->debug = mask;
	OUTPUT:
	RETVAL

int
_tie_objects(yes)
	int yes
	CODE:
	dOSP ;
	RETVAL = osp->tie_objects;
	osp->tie_objects = yes;
	OUTPUT:
	RETVAL

SV *
set_stargate(code)
	SV *code
	CODE:
	dOSP ;
	ST(0) = osp->stargate? sv_2mortal(newSVsv(osp->stargate)):&sv_undef;
	if (!osp->stargate) { osp->stargate = newSVsv(code); }
	else { sv_setsv(osp->stargate, code); }

char *
release_name()
	CODE:
	RETVAL = (char*) objectstore::release_name();
	OUTPUT:
	RETVAL

int
release_major()
	CODE:
	RETVAL = objectstore::release_major();
	OUTPUT:
	RETVAL

int
release_minor()
	CODE:
	RETVAL = objectstore::release_minor();
	OUTPUT:
	RETVAL

int
release_maintenance()
	CODE:
	RETVAL = objectstore::release_maintenance();
	OUTPUT:
	RETVAL

int
network_servers_available()
	CODE:
	RETVAL = objectstore::network_servers_available();
	OUTPUT:
	RETVAL

int
get_page_size()
	CODE:
	RETVAL = objectstore::get_page_size();
	OUTPUT:
	RETVAL

os_database *
_lookup(path, mode)
	char *path;
	int mode;
	CODE:
	dOSP;
	char *CLASS = ObjStore_Database;
	int ok=0;
	TIX_HANDLE(all_exceptions)
	  RETVAL = os_database::lookup(path, mode); ok=1;
	TIX_EXCEPTION
	  CAPTURE_TIX_REPORT
	TIX_END_HANDLE
	if (!ok) croak("ObjectStore: %s", SvPV(osp->errsv, na));
	RETVAL->set_check_illegal_pointers(1);
	OUTPUT:
	RETVAL

double
get_unassigned_address_space()
	CODE:
	RETVAL = objectstore::get_unassigned_address_space(); //64bit? XXX
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
	os_server **svrs = new os_server*[num];
	objectstore::get_all_servers(num, svrs, num);
	EXTEND(sp, num);
	int xx;
	for (xx=0; xx < num; xx++) {
		PUSHs(sv_setref_pv(sv_newmortal() , CLASS, svrs[xx] ));
	}
	delete [] svrs;

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
	delete THIS;

int
osp_txn::deadlocked()
	CODE:
	RETVAL = THIS->deadlocked;
	OUTPUT:
	RETVAL

int
osp_txn::top_level()
	CODE:
	RETVAL = THIS->up == 0;
	OUTPUT:
	RETVAL

void
osp_txn::abort()

void
osp_txn::commit()

char *
SEGV_reason()
	CODE:
	dOSP ; dTXN ;
	if (!(txn && txn->report)) XSRETURN_UNDEF;
	RETVAL = txn->report;
	OUTPUT:
	RETVAL

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

char *
osp_txn::get_type()
	CODE:
	switch (THIS->tt) {
	case os_transaction::abort_only: RETVAL = "abort_only"; break;
	case os_transaction::read_only: RETVAL = "read"; break;
	case os_transaction::update: RETVAL = "update"; break;
	default: croak("os_transaction::get_type(): unknown transaction type");
	}
	OUTPUT:
	RETVAL

void
osp_txn::prepare_to_commit()

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
	int st = objectstore::get_lock_status(ospv);
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
	if (num == 0) XSRETURN_EMPTY;
	os_database **dbs = new os_database*[num];
	THIS->get_databases(num, dbs, num);
	EXTEND(sp, num);
	int xx;
	for (xx=0; xx < num; xx++) {
		PUSHs(sv_setref_pv( sv_newmortal() , CLASS, dbs[xx] ));
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
	int ok=0;
	TIX_HANDLE(all_exceptions)
	  THIS->open(read_only); ok=1;
	TIX_EXCEPTION
	  CAPTURE_TIX_REPORT
	TIX_END_HANDLE
	if (!ok) croak("ObjectStore: %s", SvPV(osp->errsv, na));
	XSRETURN_YES;

void
os_database::_open_mvcc()
	PPCODE:
	dOSP;
	int ok=0;
	TIX_HANDLE(all_exceptions)
	  THIS->open_mvcc(); ok=1;
	TIX_EXCEPTION
	  CAPTURE_TIX_REPORT
	TIX_END_HANDLE
	if (!ok) croak("ObjectStore: %s", SvPV(osp->errsv, na));
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

void
os_database::_allow_external_pointers(yes)
	int yes
	CODE:
	// DO NOT USE THIS!
	THIS->allow_external_pointers(yes);
	// WARNING WARNING

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

int
os_database::is_writable()

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
	if (num == 0) XSRETURN_EMPTY;
	os_segment **segs = new os_segment*[num];
	THIS->get_all_segments(num, segs, num);
	EXTEND(sp, num);
	int xx;
	for (xx=0; xx < num; xx++) {
		PUSHs(sv_setref_pv( sv_newmortal() , CLASS, segs[xx] ));
	}
	delete [] segs;

void
os_database::_PRIVATE_ROOT()
	PPCODE:
	dOSP ;
	os_database_root *rt = THIS->find_root(private_root_name);
	if (!rt && osp->can_update()) {
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
	os_database_root **roots = new os_database_root*[num];
	THIS->get_all_roots(num, roots, num);
	for (int xx=0; xx < num; xx++) {
	  assert(roots[xx]);
	  char *nm = roots[xx]->get_name();
	  int priv = strEQ(nm, private_root_name);
	  if (!priv) XPUSHs(sv_setref_pv( sv_newmortal(), CLASS, roots[xx] ));
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
	if (!THIS) XSRETURN_UNDEF;
	OSSV *ossv = (OSSV*) THIS->get_value(OSSV::get_os_typespec());
	DEBUG_root(warn("%p->get_value() = OSSV=%p", THIS, ossv));
	dOSP ;
	SV *ret = osp->ossv_2sv(ossv);
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
	ossv_bridge *br = osp->sv_2bridge(sv, 1, WHERE);
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
os_database::create_segment()
	PREINIT:
	char *CLASS = ObjStore_Segment;

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

#-----------------------------# Bridge

MODULE = ObjStore	PACKAGE = ObjStore::Bridge

void
ossv_bridge::DESTROY()
	CODE:
	THIS->release();

#-----------------------------# UNIVERSAL

MODULE = ObjStore	PACKAGE = ObjStore::UNIVERSAL

int
_is_persistent(sv)
	SV *sv;
	CODE:
	dOSP;
	ossv_bridge *br = osp->sv_2bridge(sv, 0);
	RETVAL = br != 0;
	OUTPUT:
	RETVAL

void
_pstringify(THIS, ...)
	SV *THIS;
	PROTOTYPE: $;$$
	PPCODE:
	dOSP;
	ossv_bridge *br = osp->sv_2bridge(THIS, 0);
	SV *ret;
	if (!br) {
	  STRLEN len;
	  int amagic = SvAMAGIC(THIS);  // concurrency problem? XXX
	  SvAMAGIC_off(THIS);
	  char *str = sv_2pv(THIS, &len);
	  if (amagic) SvAMAGIC_on(THIS);
	  if (!str) XSRETURN_UNDEF;
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
	ossv_bridge *b1 = osp->sv_2bridge(a1, 0);
	ossv_bridge *b2 = osp->sv_2bridge(a2, 0);
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
	ossv_bridge *b1 = osp->sv_2bridge(a1, 0);
	ossv_bridge *b2 = osp->sv_2bridge(a2, 0);
	RETVAL = !b1 || !b2 || b1->ospv() != b2->ospv();
	OUTPUT:
	RETVAL

void
OSSVPV::_refcnt()
	PPCODE:
	XPUSHs(sv_2mortal(newSViv(THIS->_refs + THIS->_weak_refs)));

void
OSSVPV::_blessto_slot(...)
	PROTOTYPE: ;$
	PPCODE:
	PUTBACK;
	if (items == 2) {
	  ossv_bridge *br = osp->sv_2bridge(ST(1), 1);
	  OSSVPV *nval = (OSSVPV*) br->ospv();
	  nval->REF_inc();
	  if (PvBLESS2(THIS) && THIS->classname)
	    ((OSSVPV*)THIS->classname)->REF_dec();
	  PvBLESS2_on(THIS);
	  THIS->classname = (char*)nval;
	  ((OSSVPV*)THIS->classname)->REF_inc();
	}
	if (!PvBLESS2(THIS) || GIMME_V == G_VOID) return;
	SV *ret = osp->ospv_2sv((OSSVPV*)THIS->classname);
	SPAGAIN;
	XPUSHs(ret);

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
OSSVPV::get_pointer_numbers()
	PPCODE:
	os_unsigned_int32 n1,n2,n3;
	objectstore::get_pointer_numbers(THIS, n1, n2, n3);
	XPUSHs(sv_2mortal(newSVpvf("%08p%08p", n1, n3)));

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
	PUTBACK ;
	os_segment *seg = osp->sv_2segment(sv1);
	SV *ret = osp->ospv_2sv(THIS->new_cursor(seg));
	SPAGAIN ;
	XPUSHs(ret);

#-----------------------------# AV

MODULE = ObjStore	PACKAGE = ObjStore::AV

void
OSPV_Generic::FETCH(xx)
	int xx;
	PPCODE:
	SV **savesp = SP;
	PUTBACK ;
	SV *ret = osp->ossv_2sv(THIS->FETCHi(xx));
	SPAGAIN ;
	assert(SP == savesp);
	XPUSHs(ret);

void
OSPV_Generic::STORE(xx, nval)
	int xx;
	SV *nval;
	PPCODE:
	SV **savesp = SP;
	PUTBACK ;
	SV *ret = osp->ossv_2sv(THIS->STOREi(xx, nval));
	SPAGAIN ;
	assert(SP == savesp);
	if (ret) XPUSHs(ret);

void
OSPV_Generic::_Pop()
	PPCODE:
	PUTBACK ;
	SV *ret = THIS->Pop();
	SPAGAIN ;
	if (ret) XPUSHs(ret);

void
OSPV_Generic::_Push(nval)
	SV *nval;
	CODE:
	THIS->Push(nval);

void
OSPV_Generic::_Shift(nval)
	SV *nval;
	CODE:
	THIS->Shift(nval);

#-----------------------------# HV

MODULE = ObjStore	PACKAGE = ObjStore::HV

void
OSPV_Generic::FETCH(key)
	char *key;
	PPCODE:
	SV **savesp = SP;
	PUTBACK ;
	SV *ret = THIS->FETCHp(key);
	SPAGAIN ;
	assert(SP == savesp);
	if (ret) XPUSHs(ret);

void
OSPV_Generic::STORE(key, nval)
	char *key;
	SV *nval;
	PPCODE:
	SV **savesp = SP;
	PUTBACK ;
	SV *ret = THIS->STOREp(key, nval);
	SPAGAIN ;
	assert(SP == savesp);
	if (ret) XPUSHs(ret);

void
OSPV_Generic::DELETE(key)
	char *key

int
OSPV_Generic::EXISTS(key)
	char *key

void
OSPV_Generic::FIRSTKEY()
	PPCODE:
	PUTBACK ;
	SV *ret = THIS->FIRST( THIS_bridge );
	SPAGAIN ;
	XPUSHs(ret);

void
OSPV_Generic::NEXTKEY(...)
	PPCODE:
	if (items > 2) croak("NEXTKEY: too many arguments");
	PUTBACK ;
	SV *ret = THIS->NEXT( THIS_bridge );
	SPAGAIN ;
	XPUSHs(ret);

void
OSPV_Generic::CLEAR()

#-----------------------------# Set

MODULE = ObjStore	PACKAGE = ObjStore::Set

void
OSPV_Generic::add(...)
	CODE:
	for (int xx=1; xx < items; xx++) THIS->add(ST(xx));

int
OSPV_Generic::contains(val)
	SV *val;

void
OSPV_Generic::rm(nval)
	SV *nval

SV *
OSPV_Generic::first()
	CODE:
	ST(0) = THIS->FIRST( THIS_bridge );  //buggy

SV *
OSPV_Generic::next()
	CODE:
	ST(0) = THIS->NEXT( THIS_bridge );  //buggy

#-----------------------------# Ref

MODULE = ObjStore	PACKAGE = ObjStore::Ref

os_database *
OSPV_Ref2::_get_database()
	PREINIT:
	char *CLASS = ObjStore_Database;
	CODE:				//should be just like lookup
	int ok=0;
	TIX_HANDLE(all_exceptions)
	  RETVAL = THIS->get_database(); ok=1;
	TIX_EXCEPTION
	  CAPTURE_TIX_REPORT
	TIX_END_HANDLE
	if (!ok) croak("ObjectStore: %s", SvPV(osp->errsv, na));
	RETVAL->set_check_illegal_pointers(1);
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
	PUTBACK ;
	SV *sv = osp->ospv_2sv(THIS->focus());
	SPAGAIN ;
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
OSPV_Cursor::seek_pole(side)
	SV *side
	CODE:
	if (SvPOKp(side)) {
	  char *str = SvPV(side, na);
	  if (strEQ(str, "end")) THIS->seek_pole(1);
	} else if (SvIOK(side) && SvIV(side)==0) {
	  THIS->seek_pole(0);
	} else croak("seek_pole");

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

