/*
Copyright (c) 1997 Joshua Nathaniel Pritikin.  All rights reserved.
This package is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.
*/

#include "osperl.h"


static char *private_root_name = "_osperl_private";

// factor char *CLASS = "..."; XXX
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

void destroy_transaction(void *txn)
{ delete (osp_txn*)txn; }

// lookup static symbol (not needed if dynamically linked)
extern "C" XS(boot_ObjStore__GENERIC);

//----------------------------- ObjStore

MODULE = ObjStore	PACKAGE = ObjStore

BOOT:
  // Nuke the following line if you are dynamic-linking ObjStore::GENERIC
  newXS("ObjStore::GENERIC::bootstrap", boot_ObjStore__GENERIC, file);
  //
  SV* me = perl_get_sv("0", FALSE);
  assert(me);
  objectstore::set_client_name(SvPV(me, na));
  objectstore::initialize();		// should delay boot for flexibility? XXX
  //objectstore::set_incremental_schema_installation(1);
#ifdef USE_THREADS
  die("No threads support yet");
#else
  osp_thr::boot_single();
#endif
  newXSproto("ObjStore::translate", XS_ObjStore_translate, file, "$$");

SV *
reftype(ref)
	SV *ref
	CODE:
	if (!SvROK(ref)) XSRETURN_NO;
	ref = SvRV(ref);
	XSRETURN_PV(sv_reftype(ref, 0));

SV *
blessed(ref)
	SV *ref
	CODE:
	if (!SvROK(ref)) XSRETURN_UNDEF;
	ref = SvRV(ref);
	if (SvOBJECT(ref)) XSRETURN_PV(HvNAME(SvSTASH(ref)));
	else XSRETURN_NO;

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
	char *CLASS = ObjStore_Database;
	RETVAL = os_database::lookup(path, mode);
	OUTPUT:
	RETVAL

double
get_unassigned_address_space()
	CODE:
	RETVAL = objectstore::get_unassigned_address_space();
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
	CODE:
	THIS->open(read_only);

void
os_database::_open_mvcc()
	CODE:
	THIS->open_mvcc();

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

int
os_database::size()

int
os_database::size_in_sectors()

time_t
os_database::time_created()

int
os_database::is_open()

int
os_database::is_open_mvcc()

int
os_database::is_open_read_only()

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
	if (strEQ(name, private_root_name)) {
	  warn("The private root is, well, private");
	  XSRETURN_UNDEF;
	}
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

SV *
os_database_root::get_value()
	CODE:
	if (!THIS) XSRETURN_UNDEF;
	OSSV *ossv = (OSSV*) THIS->get_value(OSSV::get_os_typespec());
	DEBUG_root(warn("%p->get_value() = OSSV=%p", THIS, ossv));
	dOSP ;
	ST(0) = osp->ossv_2sv(ossv);

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
os_segment::database_of()
	PREINIT:
	char *CLASS = ObjStore_Database;

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

#-----------------------------# UNIVERSAL

MODULE = ObjStore	PACKAGE = ObjStore::UNIVERSAL

void
OSSVPV::_refcnt()
	PPCODE:
	XPUSHs(sv_2mortal(newSViv(THIS->_refs + THIS->_weak_refs)));

void
OSSVPV::set_weak_refcnt_to_zero()
	CODE:
	while (THIS->_weak_refs > 0) THIS->wREF_dec();

void
ABSORB(cname, sv)
	char *cname
	SV *sv
	PPCODE:
	PUTBACK ;
	SV *sv_copy = sv_2mortal(newSVsv(sv));
	dOSP ;
	ossv_bridge *br = osp->sv_2bridge(sv, 0);
	if (br) {
	  OSSVPV *pv = br->ospv();
	  pv->_bless(cname);
	} else {
	  DEBUG_bless(warn("ABSORB(%s, {...})", cname));
	}
	SPAGAIN ;
	PUSHMARK(SP) ;
	XPUSHs(sv_2mortal(newSVpv(cname, 0))) ;
	XPUSHs(sv_copy) ;
	PUTBACK ;
	int count = perl_call_method("SUPER::ABSORB", G_SCALAR) ;
	assert(count == 1);
	return;

char *
OSSVPV::_blessed_to()
	CODE:
	RETVAL = THIS->_blessed_to(0);
	OUTPUT:
	RETVAL

SV *
OSSVPV::_pstringify(...)
	PROTOTYPE: ;$$
	CODE:
	SV *sv = SvRV(ST(0));
	char *rtype = sv_reftype(sv, 0);
	char *blessed_to = sv_reftype(sv, 1);
	ST(0) = sv_2mortal(newSVpvf("%s=%s(0x%x)",blessed_to,rtype,THIS));

os_database *
OSSVPV::database_of()
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

char *
OSSVPV::os_class()
	CODE:
	RETVAL = THIS->base_class();
	OUTPUT:
	RETVAL

void
OSSVPV::get_pointer_numbers()
	PPCODE:
	os_unsigned_int32 n1,n2,n3;
	objectstore::get_pointer_numbers(THIS, n1, n2, n3);
	XPUSHs(sv_2mortal(newSVpvf("%08p%08p", n1, n3)));

SV *
OSSVPV::_new_ref(sv1)
	SV *sv1
	CODE:
	os_segment *seg = osp->sv_2segment(sv1);
	ST(0)=osp->ospv_2sv(new(seg,OSPV_Ref::get_os_typespec()) OSPV_Ref(THIS));

#-----------------------------# UNIVERSAL::Container

MODULE = ObjStore	PACKAGE = ObjStore::UNIVERSAL::Container

RAW_STRING *
OSPV_Container::_get_raw_string(key)
	char *key;
	CODE:
	char *CLASS = "ObjStore::RAW_STRING";
	RETVAL = THIS->_get_raw_string(key);
	OUTPUT:
	RETVAL

double
OSPV_Container::_percent_filled()
	CODE:
	RETVAL = THIS->_percent_filled();
	if (RETVAL < 0 || RETVAL > 1) XSRETURN_UNDEF;
	OUTPUT:
	RETVAL

int
OSPV_Generic::_count()

SV *
OSPV_Container::_new_cursor(sv1)
	SV *sv1;
	CODE:
	os_segment *seg = osp->sv_2segment(sv1);
	ST(0) = osp->ospv_2sv(THIS->new_cursor(seg));

#-----------------------------# AV

MODULE = ObjStore	PACKAGE = ObjStore::AV

SV *
OSPV_Generic::FETCH(xx)
	int xx;
	CODE:
	ST(0) = THIS->FETCHi(xx);

SV *
OSPV_Generic::STORE(xx, nval)
	int xx;
	SV *nval;
	CODE:
	SV *ret;
	ret = THIS->STOREi(xx, nval);
	if (ret) { ST(0) = ret; }
	else     { XSRETURN_EMPTY; }

SV *
OSPV_Generic::_Pop()
	CODE:
	ST(0) = THIS->Pop();

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

SV *
OSPV_Generic::FETCH(key)
	char *key;
	CODE:
	ST(0) = THIS->FETCHp(key);

SV *
OSPV_Generic::STORE(key, nval)
	char *key;
	SV *nval;
	CODE:
	SV *ret;
	ret = THIS->STOREp(key, nval);
	if (ret) { ST(0) = ret; }
	else     { XSRETURN_EMPTY; }

void
OSPV_Generic::DELETE(key)
	char *key

int
OSPV_Generic::EXISTS(key)
	char *key

SV *
OSPV_Generic::FIRSTKEY()
	CODE:
	ST(0) = THIS->FIRST( THIS_bridge );

SV *
OSPV_Generic::NEXTKEY(...)
	CODE:
	if (items > 2) croak("NEXTKEY: too many arguments");
	ST(0) = THIS->NEXT( THIS_bridge );

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
	ST(0) = THIS->FIRST( THIS_bridge );

SV *
OSPV_Generic::next()
	CODE:
	ST(0) = THIS->NEXT( THIS_bridge );

#-----------------------------# Ref

MODULE = ObjStore	PACKAGE = ObjStore::UNIVERSAL::Ref

os_database *
OSPV_Ref::get_database()
	PREINIT:
	char *CLASS = ObjStore_Database;

int
OSPV_Ref::_broken()

int
OSPV_Ref::deleted()

void
OSPV_Ref::focus()
	PPCODE:
	PUTBACK;
	SV *sv = osp->ospv_2sv(THIS->focus());
	SPAGAIN;
	XPUSHs(sv);

#-----------------------------# Cursor

MODULE = ObjStore	PACKAGE = ObjStore::UNIVERSAL::Cursor

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
