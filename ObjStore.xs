/*
Copyright (c) 1997 Joshua Nathaniel Pritikin.  All rights reserved.
This package is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.
*/

#include <assert.h>
#include <string.h>
#include "osperl.hh"

//----------------------------- Constants

static auto_open_mode_enum str_2auto_open(char *str)
{
  if (strcmp(str, "read")==0) return objectstore::auto_open_read_only;
  if (strcmp(str, "mvcc")==0) return objectstore::auto_open_mvcc;
  if (strcmp(str, "update")==0) return objectstore::auto_open_update;
  if (strcmp(str, "disable")==0) return objectstore::auto_open_disable;
  croak("str_2auto_open: %s unrecognized", str);
}

static os_fetch_policy str_2fetch(char *str)
{
  if (strcmp(str, "segment")==0) return os_fetch_segment;
  if (strcmp(str, "page")==0) return os_fetch_page;
  if (strcmp(str, "stream")==0) return os_fetch_stream;
  croak("str_2fetch: %s unrecognized", str);
}

static objectstore_lock_option str_2lock_option(char *str)
{
  if (strcmp(str, "as_used")==0) return objectstore::lock_as_used;
  if (strcmp(str, "read")==0) return objectstore::lock_segment_read;
  if (strcmp(str, "write")==0) return objectstore::lock_segment_write;
  croak("str_2lock_option: %s unrecognized", str);
}

//----------------------------- Exceptions

DEFINE_EXCEPTION(perl_exception,"Perl-ObjStore Exception",0);
static tix_handler *current_handler=0;
static int got_os_exception;
static int deadlocked;

static void
osperl_exception_hook(tix_exception_p cause, os_int32 value, os_char_p report)
{
  dSP ;
  PUSHMARK(sp) ;
  XPUSHs(sv_2mortal(newSVpv(report, 0)));
  PUTBACK;
  SV *hdlr = perl_get_sv("ObjStore::EXCEPTION", 0);
  assert(hdlr);

  if (current_handler) {	// OS exception within a transaction; no sweat

    got_os_exception=1;
    current_handler->_unwind_part_1(cause, value, report);
    perl_call_sv(hdlr, G_DISCARD);

  } else {			// emergency diagnostics

    perl_call_sv(hdlr, G_DISCARD);
    exit(1);
  }
}

static void
osperl_abort_top_level()
{
  os_transaction *txn;
  txn = os_transaction::get_current();
  while (txn) {
    os_transaction::abort(txn);
    delete txn;
    txn = os_transaction::get_current();
  }
}

static int txn_nested;

int osperl::txn_is_ok;
int osperl::is_update_txn;

static void
osperl_transaction(os_transaction::transaction_type_enum tt,
		   os_transaction::transaction_scope_enum scope_in)
{
  os_transaction *txn;
  int retries;

  dSP; dMARK;
  I32 items = SP - MARK;
  if (items != 1) croak("Usage: ObjStore::try_*(code)");

  SV *code = POPs ;

  if (os_transaction::get_current()) die("Nested transactions are unsupported");

  if (!os_transaction::get_current()) {
    //    warn("begin top");
    retries=0;
    txn_nested=0;
    deadlocked=0;
    osperl::txn_is_ok = 1;
  }

  PUTBACK ;
  
  RETRY: {
    // Since perl_exception has no parent and is never signalled, we always
    // get an unhandled exception when objectstore tries to throw an exception.

    tix_handler bang(&perl_exception);
    got_os_exception=0;
    tix_handler *old_handler = current_handler;
    current_handler = &bang;

    osperl::is_update_txn = (tt != os_transaction::read_only);
    os_transaction::begin(tt, scope_in, os_transaction::get_current());
    
    SPAGAIN ;
    ENTER ;
    SAVETMPS;
    PUSHMARK(sp) ;
    PUTBACK ;
    ++ txn_nested;
    int count = perl_call_sv(code, G_NOARGS|G_EVAL|G_DISCARD);
    assert(count==0);
    -- txn_nested;
    txn = os_transaction::get_current();
    osperl::txn_is_ok = (txn && !txn->is_aborted());
    osperl::destroy_bridge();
    //    warn("return to level %d", txn_nested);
    FREETMPS ;
    LEAVE ;
    
    if (got_os_exception) {
      got_os_exception=0;
      current_handler->_unwind_part_2();
      osperl_abort_top_level();
      tix_exception *ex = current_handler->get_exception();
      if (ex && ex->ancestor_of(&err_deadlock)) {  //deadlock
	//	warn("deadlock");
//	SV *error = GvSV(errgv);
//	sv_setpv(error, current_handler->get_report());
	deadlocked=1;
      }
    }
    if (osperl::rethrow_exceptions && !deadlocked && SvTRUE(GvSV(errgv))) {
      char *tmps = SvPV(GvSV(errgv), na);
      if (!tmps || !*tmps) tmps = "Died";
      die("%s", tmps);
    }
    current_handler=old_handler;
    txn = os_transaction::get_current();
    //    warn("transaction=0x%x", txn);
    if (!txn) {
      if (txn_nested) {
	char *tmps = SvPV(GvSV(errgv), na);
	if (!tmps || !*tmps) tmps = "Died";
	//	warn("pop transaction");
	die("%s", tmps);
      }
    } else {
      if (osperl::txn_is_ok && tt != os_transaction::abort_only)
        os_transaction::commit(txn);
      else
	os_transaction::abort(txn);
      delete txn;
    }
  }
  if (txn_nested==0 && deadlocked) {
    deadlocked=0;
    if (retries++ < os_transaction::get_max_retries()) {
      goto RETRY;
    } else {
      if (osperl::rethrow_exceptions) {
	char *tmps = SvPV(GvSV(errgv), na);
	if (!tmps || !*tmps) tmps = "Died";
	die("%s", tmps);
      }
    }
  }
  //  if (!txn_nested) warn("end top");
}

XS(XS_ObjStore_try_read)
{ osperl_transaction(os_transaction::read_only, os_transaction::local); }

XS(XS_ObjStore_try_update)
{ osperl_transaction(os_transaction::update, os_transaction::local); }

XS(XS_ObjStore_try_abort_only)
{ osperl_transaction(os_transaction::abort_only, os_transaction::local); }

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
  objectstore::set_incremental_schema_installation(1);
  objectstore::set_thread_locking(0);	// threads support...?!
  tix_exception::set_unhandled_exception_hook(osperl_exception_hook);
  osperl::boot_thread();
  newXSproto("ObjStore::try_read", XS_ObjStore_try_read, file, "&");
  newXSproto("ObjStore::try_update", XS_ObjStore_try_update, file, "&");
  newXSproto("ObjStore::try_abort_only", XS_ObjStore_try_abort_only, file, "&");

SV *
reftype(ref)
	SV *ref
	CODE:
	if (!SvROK(ref)) XSRETURN_NO;
	ref = SvRV(ref);
	XSRETURN_PV(sv_reftype(ref, 0));

char *
schema_dir(...)
	CODE:
	RETVAL = SCHEMADIR;
	OUTPUT:
	RETVAL

int
_enable_blessings(yes)
	int yes
	CODE:
	RETVAL = osperl::enable_blessings;
	osperl::enable_blessings = yes;
	OUTPUT:
	RETVAL

int
_tie_objects(yes)
	int yes
	CODE:
	RETVAL = osperl::tie_objects;
	osperl::tie_objects = yes;
	OUTPUT:
	RETVAL

SV *
set_stargate(code)
	SV *code
	CODE:
	ST(0) = osperl::stargate? sv_2mortal(newSVsv(osperl::stargate)):&sv_undef;
	if (!osperl::stargate) { osperl::stargate = newSVsv(code); }
	else { sv_setsv(osperl::stargate, code); }

void
rethrow_exceptions(yes)
	int yes;
	CODE:
	osperl::rethrow_exceptions = yes;

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

void
set_auto_open_mode(mode, fp, ...)
	char *mode
	char *fp
	PROTOTYPE: $$;$
	CODE:
	os_int32 sz = 0;
	if (items == 3) sz = SvIV(ST(2));
	objectstore::set_auto_open_mode(str_2auto_open(mode), str_2fetch(fp), sz);

int
get_page_size()
	CODE:
	RETVAL = objectstore::get_page_size();
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

os_database *
database_of(ospv)
	OSSVPV *ospv
	CODE:
	char *CLASS = "ObjStore::Database";
	RETVAL = os_database::of(ospv);
	OUTPUT:
	RETVAL

os_segment *
segment_of(sv)
	SV *sv
	CODE:
	char *CLASS = "ObjStore::Segment";
	RETVAL = osperl::sv_2segment(sv);
	OUTPUT:
	RETVAL

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
	char *CLASS = "ObjStore::Database";
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

os_database *
open(pathname, read_only, create_mode)
	char *pathname
	int read_only
	int create_mode
	CODE:
	char *CLASS = "ObjStore::Database";
	RETVAL = os_database::open(pathname, read_only, create_mode);
	OUTPUT:
	RETVAL

int
get_n_databases()
	CODE:
	RETVAL = os_database::get_n_databases();
	OUTPUT:
	RETVAL

MODULE = ObjStore	PACKAGE = ObjStore::Database

void
os_database::close()

void
os_database::destroy()

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

int
os_database::is_open()

void
os_database::open_mvcc()

int
os_database::is_open_mvcc()

int
os_database::is_open_read_only()

int
os_database::is_writable()

void
os_database::set_opt_cache_lock_mode(yes)
	int yes

void
os_database::set_fetch_policy(policy, ...)
	char *policy;
	PROTOTYPE: $;$
	CODE:
	int bytes=4096;
	if (items == 2) bytes = SvIV(ST(1));
	THIS->set_fetch_policy(str_2fetch(policy), bytes);

void
os_database::set_lock_whole_segment(policy)
	char *policy;
	CODE:
	THIS->set_lock_whole_segment(str_2lock_option(policy));

os_database *
of(ospv)
	OSSVPV *ospv
	CODE:
	char *CLASS = "ObjStore::Database";
	RETVAL = os_database::of(ospv);
	OUTPUT:
	RETVAL

os_segment *
os_database::get_default_segment()
	CODE:
	char *CLASS = "ObjStore::Segment";
	RETVAL = THIS->get_default_segment();
	OUTPUT:
	RETVAL

os_segment *
os_database::get_segment(num)
	int num
	CODE:
	char *CLASS = "ObjStore::Segment";
	RETVAL = THIS->get_segment(num);
	OUTPUT:
	RETVAL

void
os_database::get_all_segments()
	PPCODE:
	char *CLASS = "ObjStore::Segment";
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
os_database::get_all_roots()
	PPCODE:
	char *CLASS = "ObjStore::Root";
	os_int32 num = THIS->get_n_roots();
	if (num == 0) XSRETURN_EMPTY;
	os_database_root **roots = new os_database_root*[num];
	THIS->get_all_roots(num, roots, num);
	EXTEND(sp, num);
	int xx;
	for (xx=0; xx < num; xx++) {
		PUSHs(sv_setref_pv( sv_newmortal(), CLASS, roots[xx] ));
	}
	delete [] roots;

#-----------------------------# Root

MODULE = ObjStore	PACKAGE = ObjStore::Database

os_database_root *
os_database::create_root(name)
	char *name
	PREINIT:
	char *CLASS = "ObjStore::Root";

os_database_root *
os_database::find_root(name)
	char *name
	PREINIT:
	char *CLASS = "ObjStore::Root";

MODULE = ObjStore	PACKAGE = ObjStore::Root

void
os_database_root::destroy()
	CODE:
	delete (OSSV*) THIS->get_value();
	delete THIS;

char *
os_database_root::get_name()

SV *
os_database_root::get_value()
	CODE:
	if (!THIS) XSRETURN_UNDEF;
	OSSV *ossv = (OSSV*) THIS->get_value(OSSV::get_os_typespec());
	ST(0) = osperl::ossv_2sv(ossv);

void
os_database_root::set_value(sv)
	SV *sv
	CODE:
	OSSV *ossv = (OSSV*) THIS->get_value(OSSV::get_os_typespec());
	if (ossv) {
	  *ossv = sv;
	} else {
	  ossv = osperl::plant_sv(os_segment::of(THIS), sv);
	  THIS->set_value(ossv, OSSV::get_os_typespec());
	}

#-----------------------------# Transaction

MODULE = ObjStore	PACKAGE = ObjStore::Transaction

int
os_transaction::top_level()

os_transaction *
get_current()
	CODE:
	char *CLASS = "ObjStore::Transaction";
	RETVAL = os_transaction::get_current();
	OUTPUT:
	RETVAL

os_transaction *
os_transaction::get_parent()
	CODE:
	char *CLASS = "ObjStore::Transaction";
	RETVAL = THIS->get_parent();
	OUTPUT:
	RETVAL

char *
os_transaction::get_type()
	CODE:
	switch (THIS->get_type()) {
	case os_transaction::abort_only: RETVAL = "abort_only"; break;
	case os_transaction::read_only: RETVAL = "read"; break;
	case os_transaction::update: RETVAL = "update"; break;
	default: croak("os_transaction::get_type(): unknown transaction type");
	}
	OUTPUT:
	RETVAL

void
os_transaction::prepare_to_commit()

int
os_transaction::is_prepare_to_commit_invoked()

int
os_transaction::is_prepare_to_commit_completed()

MODULE = ObjStore	PACKAGE = ObjStore

void
set_transaction_priority(pri)
	int pri;
	CODE:
	objectstore::set_transaction_priority(pri);

void
set_max_retries(cnt)
	int cnt;
	CODE:
	os_transaction::set_max_retries(cnt);

int
get_max_retries()
	CODE:
	RETVAL = os_transaction::get_max_retries();
	OUTPUT:
	RETVAL

int
abort_in_progress()
	CODE:
	RETVAL = objectstore::abort_in_progress();
	OUTPUT:
	RETVAL

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
	default: XSRETURN_UNDEF;
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

#-----------------------------# Segment

MODULE = ObjStore	PACKAGE = ObjStore::Database

os_segment *
os_database::create_segment()
	PREINIT:
	char *CLASS = "ObjStore::Segment";

MODULE = ObjStore	PACKAGE = ObjStore::Segment

void
os_segment::destroy()
	CODE:
	if (!THIS->is_empty()) croak("attempt to destroy unempty os_segment");
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

char *
os_segment::get_comment()

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
	if (items == 2) bytes = SvIV(ST(1));
	THIS->set_fetch_policy(str_2fetch(policy), bytes);

void
os_segment::set_lock_whole_segment(policy)
	char *policy;
	CODE:
	THIS->set_lock_whole_segment(str_2lock_option(policy));

os_segment *
of(sv)
	SV *sv
	CODE:
	char *CLASS = "ObjStore::Segment";
	RETVAL = osperl::sv_2segment(sv);
	OUTPUT:
	RETVAL

#-----------------------------# Magic

MODULE = ObjStore	PACKAGE = ObjStore::Bridge

void
ossv_bridge::DESTROY()

#-----------------------------# UNIVERSAL

MODULE = ObjStore	PACKAGE = ObjStore::UNIVERSAL

void
OSSVPV::_bless(pstr)
	char *pstr
	CODE:
	THIS->_bless(pstr);

char *
OSSVPV::_ref()
	CODE:
	RETVAL = THIS->get_blessing();
	OUTPUT:
	RETVAL

int
OSSVPV::_refcnt()
	CODE:
	RETVAL = THIS->_refs;
	OUTPUT:
	RETVAL

SV *
OSSVPV::_pstringify(...)
	PROTOTYPE: ;$$
	CODE:
	char *rtype = sv_reftype(SvRV(ST(0)), 0);
	ST(0) = sv_2mortal(newSVpvf("%s=%s(0x%x)",THIS->get_blessing(),rtype,THIS));

SV *
OSSVPV::_paddress(...)
	CODE:
	ST(0) = sv_2mortal(newSViv((long) THIS));

#-----------------------------# UNIVERSAL::Container

MODULE = ObjStore	PACKAGE = ObjStore::UNIVERSAL::Container

RAW_STRING *
OSSVPV::_get_raw_string(key)
	char *key;
	CODE:
	char *CLASS = "ObjStore::RAW_STRING";
	RETVAL = THIS->_get_raw_string(key);
	OUTPUT:
	RETVAL

double
OSSVPV::_percent_filled()
	CODE:
	RETVAL = THIS->_percent_filled();
	if (RETVAL < 0 || RETVAL > 1) XSRETURN_UNDEF;
	OUTPUT:
	RETVAL

SV *
OSSVPV::new_cursor(...)
	CODE:
	XSRETURN_UNDEF;
	os_segment *seg=0;
	if (items == 0) { seg = os_segment::of(THIS); }
	else if (items == 1) { seg = osperl::sv_2segment(ST(0)); }
	if (!seg)
	  croak("OSSVPV(0x%x)->new_cursor([segment]) was passed junk", THIS);
	ST(0) = osperl::ospv_2sv(THIS->new_cursor(seg));

#-----------------------------# AV

MODULE = ObjStore	PACKAGE = ObjStore::AV

SV *
OSSVPV::FETCH(xx)
	int xx;
	CODE:
	ST(0) = THIS->FETCHi(xx);

SV *
OSSVPV::STORE(xx, nval)
	int xx;
	SV *nval;
	CODE:
	SV *ret;
	ret = THIS->STOREi(xx, nval);
	if (ret) { ST(0) = ret; }
	else     { XSRETURN_EMPTY; }

int
OSSVPV::_LENGTH()

#-----------------------------# HV

MODULE = ObjStore	PACKAGE = ObjStore::HV

SV *
OSSVPV::FETCH(key)
	char *key;
	CODE:
	ST(0) = THIS->FETCHp(key);

SV *
OSSVPV::STORE(key, nval)
	char *key;
	SV *nval;
	CODE:
	SV *ret;
	ret = THIS->STOREp(key, nval);
	if (ret) { ST(0) = ret; }
	else     { XSRETURN_EMPTY; }

void
OSSVPV::DELETE(key)
	char *key

int
OSSVPV::EXISTS(key)
	char *key

SV *
OSSVPV::FIRSTKEY()
	CODE:
	ST(0) = THIS->FIRST( THIS_bridge );

SV *
OSSVPV::NEXTKEY(ign)
	char *ign;
	CODE:
	ST(0) = THIS->NEXT( THIS_bridge );

void
OSSVPV::CLEAR()

#-----------------------------# Set

MODULE = ObjStore	PACKAGE = ObjStore::Set

void
OSSVPV::add(...)
	CODE:
	for (int xx=1; xx < items; xx++) {
	  SV *ret = THIS->add(ST(xx));
	}

int
OSSVPV::contains(val)
	SV *val;

void
OSSVPV::rm(nval)
	SV *nval

SV *
OSSVPV::first()
	CODE:
	ST(0) = THIS->FIRST( THIS_bridge );

SV *
OSSVPV::next()
	CODE:
	ST(0) = THIS->NEXT( THIS_bridge );

#-----------------------------# Cursor

MODULE = ObjStore	PACKAGE = ObjStore::Cursor

SV *
OSPV_Cursor::focus()
	PPCODE:
	XPUSHs(THIS->focus());

int
OSPV_Cursor::more()

void
OSPV_Cursor::first()
	PPCODE:
	PUTBACK; THIS->first(); return;

void
OSPV_Cursor::next()
	PPCODE:
	PUTBACK; THIS->next(); return;

void
OSPV_Cursor::prev()
	PPCODE:
	PUTBACK; THIS->prev(); return;

void
OSPV_Cursor::last()
	PPCODE:
	PUTBACK; THIS->last(); return;
