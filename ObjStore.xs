/*
Copyright (c) 1997 Joshua Nathaniel Pritikin.  All rights reserved.
This package is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

What is the most efficient way to manipulate the perl stack?
*/

#include <assert.h>
#include <string.h>
#include "osperl.hh"

//----------------------------- Constants

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
static tix_handler *global_handler=0;
static int objectstore_exception;

static void osperl_exception_hook(tix_exception_p cause, os_int32 value,
	os_char_p report)
{
  dSP ;
  PUSHMARK(sp) ;
  XPUSHs(sv_2mortal(newSVpv(report, 0)));
  PUTBACK;
  SV *hdlr = perl_get_sv("ObjStore::Exception", 0);
  assert(hdlr);

  if (global_handler) {		// OS exception within a transaction; no sweat

    objectstore_exception=1;
    global_handler->_unwind_part_1(cause, value, report);
    perl_call_sv(hdlr, G_DISCARD);

  } else {			// emergency diagnostics

    perl_call_sv(hdlr, G_DISCARD);
    exit(1);
  }
}

// These XS functions are implemented directly in C++.
// It is absolutely important that they work flawlessly.

XS(XS_ObjStore_try_read)
{
	dXSARGS;
	if (items != 1) croak("Usage: ObjStore::try_read(code)");
	SP -= items;
	SV *code = ST(0);

//	ENTER ;
//	SAVETMPS;

	tix_handler bang(&perl_exception);
	objectstore_exception=0;
	tix_handler *old_handler = global_handler;
	global_handler = &bang;
	os_transaction::begin(os_transaction::read_only);

	PUSHMARK(sp) ;

	int count = perl_call_sv(code, G_NOARGS|G_EVAL|G_DISCARD);

//	SPAGAIN ;

	if (SvTRUE(GvSV(errgv))) {
	  if (objectstore_exception) global_handler->_unwind_part_2();
	  objectstore_exception=0;
	}
	os_transaction::commit();
	global_handler=old_handler;

//	PUTBACK ;
//	FREETMPS ;
//	LEAVE ;
}

XS(XS_ObjStore_try_abort_only)
{
	dXSARGS;
	if (items != 1) croak("Usage: ObjStore::try_abort_only(code)");
	SP -= items;
	SV *code = ST(0);

//	ENTER ;
//	SAVETMPS;

	tix_handler bang(&perl_exception);
	objectstore_exception=0;
	tix_handler *old_handler = global_handler;
	global_handler = &bang;
	os_transaction::begin(os_transaction::abort_only);

	PUSHMARK(sp) ;

	int count = perl_call_sv(code, G_NOARGS|G_EVAL|G_DISCARD);

//	SPAGAIN ;

	if (SvTRUE(GvSV(errgv))) {
	  if (objectstore_exception) global_handler->_unwind_part_2();
	  objectstore_exception=0;
	}
	os_transaction::abort();
	global_handler=old_handler;

//	PUTBACK ;
//	FREETMPS ;
//	LEAVE ;
}

XS(XS_ObjStore_try_update)
{
	dXSARGS;
	if (items != 1) croak("Usage: ObjStore::try_update(code)");
	SP -= items;
	SV *code = ST(0);

//	ENTER ;
//	SAVETMPS;

	tix_handler bang(&perl_exception);
	objectstore_exception=0;
	tix_handler *old_handler = global_handler;
	global_handler = &bang;
	os_transaction::begin(os_transaction::update);

	PUSHMARK(sp) ;

	int count = perl_call_sv(code, G_NOARGS|G_EVAL|G_DISCARD);

//	SPAGAIN ;

	if (SvTRUE(GvSV(errgv))) {
	  if (objectstore_exception) global_handler->_unwind_part_2();
	  objectstore_exception=0;
	  os_transaction::abort();
	} else {
	  os_transaction::commit();
	}
	global_handler=old_handler;

//	PUTBACK ;
//	FREETMPS ;
//	LEAVE ;
}

//----------------------------- ObjStore

MODULE = ObjStore	PACKAGE = ObjStore

BOOT:
  objectstore::initialize();		// should delay boot for flexibility? XXX
  objectstore::set_thread_locking(0);	// threads support...?!
  os_collection::set_thread_locking(0);
  os_index_key(hkey, hkey::rank, hkey::hash);
  tix_exception::set_unhandled_exception_hook(osperl_exception_hook);
  newXSproto("ObjStore::try_read", XS_ObjStore_try_read, file, "&");
  newXSproto("ObjStore::try_abort_only", XS_ObjStore_try_abort_only, file, "&");
  newXSproto("ObjStore::try_update", XS_ObjStore_try_update, file, "&");

static char *
ObjStore::schema_dir()
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

SV *
gateway(code)
	SV *code
	CODE:
	ST(0) = osperl::gateway? sv_2mortal(newSVsv(osperl::gateway)): &sv_undef;
	if (!osperl::gateway) { osperl::gateway = newSVsv(code); }
	else { sv_setsv(osperl::gateway, code); }

SV *
reftype(ref)
	SV *ref
	CODE:
	if (!SvROK(ref)) XSRETURN_NO;
	ref = SvRV(ref);
	XSRETURN_PV(sv_reftype(ref, 0));

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
get_page_size()
	CODE:
	RETVAL = objectstore::get_page_size();
	OUTPUT:
	RETVAL

void
begin_update()
	CODE:
	os_transaction::begin(os_transaction::update);
	warn("ObjStore::begin_update() depreciated");

void
begin_read()
	CODE:
	os_transaction::begin(os_transaction::read_only);
	warn("ObjStore::begin_read() depreciated");

void
begin_abort()
	CODE:
	os_transaction::begin(os_transaction::abort_only);
	warn("ObjStore::begin_abort() depreciated");

void
commit()
	CODE:
	os_transaction::commit();
	warn("ObjStore::commit() depreciated");

void
abort()
	CODE:
	os_transaction::abort();
	warn("ObjStore::abort() depreciated - use 'die'");

int
abort_in_progress()
	CODE:
	RETVAL = objectstore::abort_in_progress();
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
		PUSHs(sv_setref_pv( newSViv(0) , CLASS, svrs[xx] ));
	}
	delete [] svrs;

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
		PUSHs(sv_setref_pv( newSViv(0) , CLASS, dbs[xx] ));
	}
	delete [] dbs;

#-----------------------------# Database

MODULE = ObjStore	PACKAGE = ObjStore::Database

static os_database *
os_database::open(pathname, read_only, create_mode)
	char *pathname
	int read_only
	int create_mode

void
os_database::close()

void
os_database::destroy()

int
os_database::get_default_segment_size()

int
os_database::get_sector_size()

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
		PUSHs(sv_setref_pv( newSViv(0) , CLASS, segs[xx] ));
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
		PUSHs(sv_setref_pv( newSViv(0), CLASS, roots[xx] ));
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
	OSSV *ossv = (OSSV*) THIS->get_value();  // check type! XXX
	if (ossv) ossv->REF_dec();
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
	OSSV *ossv=0;
	ossv_magic *mg = osperl::sv_2magic(sv);
	if (mg) ossv = mg->force_ossv();
	if (!ossv) {
	  ossv = new(os_segment::of(THIS), OSSV::get_os_typespec()) OSSV(sv);
	  ossv->_refs=0;
	}
	OSSV *prior = (OSSV*) THIS->get_value(OSSV::get_os_typespec());
	if (prior) prior->REF_dec();
	THIS->set_value(ossv, OSSV::get_os_typespec());
	ossv->REF_inc();

#-----------------------------# Transaction

MODULE = ObjStore	PACKAGE = ObjStore::Transaction

os_transaction *
get_current()
	CODE:
	char *CLASS = "ObjStore::Transaction";
	RETVAL = os_transaction::get_current();
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
os_segment::size()

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
	if (sv_isa(sv, "ObjStore::Segment")) {
	  ST(0) = sv;  //refcnt ok?
	  XSRETURN(1);
	}
	RETVAL = osperl::sv_2segment(sv);
	OUTPUT:
	RETVAL

#-----------------------------# Magic

MODULE = ObjStore	PACKAGE = ObjStore::Magic

void
ossv_magic::DESTROY()

#-----------------------------# UNIVERSAL

MODULE = ObjStore	PACKAGE = ObjStore::UNIVERSAL

SV *
new(area, rep, card)
	os_segment *area
	char *rep
	int card
	CODE:
	// This is a low-level interface.
	// Area is the first argument and the object is not blessed
	// to user's preference.
	//
	if (card < 0) croak("Negative cardinality");
	OSSV *ossv = new(area, OSSV::get_os_typespec()) OSSV;
	ossv->_refs=0;
	ossv->new_object(rep, card);
	ST(0) = osperl::ossv_2sv(ossv);

void
OSSVPV::_bless(pstr)
	OSSV_RAW *pstr
	CODE:
	if (pstr->natural() != ossv_pv)
	  croak("Can only give literal blessings you idiot");
	assert(pstr->vptr);
	THIS->BLESS( (char*) pstr->vptr);

char *
OSSVPV::_ref()
	CODE:
	RETVAL = THIS->get_blessing();
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

int
OSSVPV::_pcmp(to_sv, ...)
	SV *to_sv
	PROTOTYPE: $;$
	CODE:
	OSSVPV *to=0;
	ossv_magic *to_mg = osperl::sv_2magic(to_sv);
	if (!to && to_mg) to = to_mg->ospv();
	if (!to && SvIOK(to_sv)) to = (OSSVPV*) SvIV(to_sv);
	if (!to) XSRETURN_UNDEF;
	if (THIS == to) RETVAL = 0;
	else if (THIS < to) RETVAL = -1;
	else RETVAL = 1;
	OUTPUT:
	RETVAL

double
OSSVPV::cardinality()
	CODE:
	RETVAL = THIS->cardinality();
	OUTPUT:
	RETVAL

double
OSSVPV::percent_unused()
	CODE:
	RETVAL = THIS->percent_unused();
	OUTPUT:
	RETVAL

#-----------------------------# HV

MODULE = ObjStore	PACKAGE = ObjStore::HV

SV *
OSSVPV::FETCH(key)
	char *key;
	CODE:
	ST(0) = THIS->FETCHp(key);

SV *
OSSVPV::_at(key)
	char *key;
	CODE:
	ST(0) = THIS->ATp(key);

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
	char *key;
	CODE:
	THIS->DELETE(key);

int
OSSVPV::EXISTS(key)
	char *key;
	CODE:
	RETVAL = THIS->EXISTS(key);
	OUTPUT:
	RETVAL

SV *
OSSVPV::FIRSTKEY()
	CODE:
	ST(0) = THIS->FIRST( THIS_magic );

SV *
OSSVPV::NEXTKEY(ign)
	char *ign;
	CODE:
	ST(0) = THIS->NEXT( THIS_magic );

void
OSSVPV::CLEAR()
	CODE:
	THIS->CLEAR();

#-----------------------------# Set

MODULE = ObjStore	PACKAGE = ObjStore::Set

void
OSSVPV::a(...)
	CODE:
	for (int xx=1; xx < items; xx++) {
	  SV *ret = THIS->ADD(ST(xx));
	}

int
OSSVPV::contains(val)
	SV *val;
	CODE:
	RETVAL = THIS->CONTAINS(val);
	OUTPUT:
	RETVAL

void
OSSVPV::r(nval)
	SV *nval;
	CODE:
	THIS->REMOVE(nval);

SV *
OSSVPV::first()
	CODE:
	ST(0) = THIS->FIRST( THIS_magic );

SV *
OSSVPV::next()
	CODE:
	ST(0) = THIS->NEXT( THIS_magic );

