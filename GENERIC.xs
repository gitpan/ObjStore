/*
Copyright (c) 1997 Joshua Nathaniel Pritikin.  All rights reserved.
This package is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

1. Gives XS interfaces tied arrays, tied hashes, and sets.
2. Provides a few sample implementations.
*/

#include <assert.h>
#include "osperl.hh"
#include "GENERIC.hh"

//#define DEBUG_HVDICT 1
//#define DEBUG_MEM_OSSVPV 1

/*--------------------------------------------- AV splash_array */

XS(XS_ObjStore__AV__new_splash_array)
{
  dXSARGS;
  if (items != 3) croak("Usage: &$create($class, $segment, $card)");
  {
    char *clname = SvPV(ST(0), na);
    os_segment *area = osperl::sv_2segment(ST(1));
    int card = (int)SvIV(ST(2));

    if (card < 0) {
      croak("Negative cardinality");
    } else if (card > 10000) {
      card = 10000;
      warn("Cardinality > 10000; try a more suitable representation");
    }

    OSSVPV *pv = new(area, OSPV_avarray::get_os_typespec()) OSPV_avarray(card);
    pv->BLESS(clname);
    ST(0) = osperl::ospv_2sv(pv);
  }    
  XSRETURN(1);
}

OSPV_avarray::OSPV_avarray(int sz)
  : av(sz,8)
{}

OSPV_avarray::~OSPV_avarray()
{
#ifdef DEBUG_MEM_OSSVPV
  warn("~OSPV_avarray %x", this);
#endif
  CLEAR();
}

char *OSPV_avarray::base_class()
{ return "ObjStore::AV"; }

int OSPV_avarray::get_perl_type()
{ return SVt_PVAV; }

double OSPV_avarray::cardinality()
{
  int good=0;
  for (int xx=0; xx < av.count(); xx++) {
    if (av[xx].natural() != ossv_undef) good++;
  }
  return good;
}

double OSPV_avarray::percent_unused()
{
  if (av.size_allocated() <= 0) return 0;
  return (av.size_allocated() - cardinality()) / (double) av.size_allocated();
}

SV *OSPV_avarray::FETCHi(int xx)
{
  return osperl::ospv_2sv(&av[xx]);
}

SV *OSPV_avarray::STOREi(int xx, SV *value)
{
  av[xx] = value;
  if (GIMME_V == G_VOID) return 0;
  return osperl::ospv_2sv(&av[xx]);
}

void OSPV_avarray::CLEAR()
{
  for (int xx=0; xx < av.count(); xx++) { av[xx].set_undef(); }
}

/*--------------------------------------------- HV splash array */

XS(XS_ObjStore__HV__new_splash_array)
{
  dXSARGS;
  if (items != 3) croak("Usage: &$create('ObjStore::HV', $segment, $card)");
  {
    char *clname = SvPV(ST(0), na);
    os_segment *area = osperl::sv_2segment(ST(1));
    int card = (int)SvIV(ST(2));

    if (card < 0) {
      croak("Negative cardinality");
    } else if (card > 10000) {
      card = 10000;
      warn("Cardinality > 10000; try a more suitable representation");
    }

    OSSVPV *pv = new(area, OSPV_hvarray::get_os_typespec()) OSPV_hvarray(card);
    pv->BLESS(clname);
    ST(0) = osperl::ospv_2sv(pv);
  }    
  XSRETURN(1);
}

OSPV_hvarray::OSPV_hvarray(int sz)
  : hv(sz,8)
{}

OSPV_hvarray::~OSPV_hvarray()
{
#ifdef DEBUG_MEM_OSSVPV
  warn("~OSPV_hvarray %x", this);
#endif
  CLEAR();
}

char *OSPV_hvarray::base_class()
{ return "ObjStore::HV"; }

int OSPV_hvarray::get_perl_type()
{ return SVt_PVHV; }

int OSPV_hvarray::index_of(char *key)
{
//  warn("OSPV_hvarray::index_of(%s)", key);
  hkey look(key, strlen(key)+1);
  int ok=0;
  for (int xx=0; xx < hv.count(); xx++) {
    if (hkey::rank(&hv[xx].hk, &look) == 0) return xx;
  }
  return -1;
}

double OSPV_hvarray::cardinality()
{
  int good=0;
  for (int xx=0; xx < hv.count(); xx++) {
    if (hv[xx].hk.valid()) good++;
  }
  return good;
}

double OSPV_hvarray::percent_unused()
{
  if (hv.size_allocated() <= 0) return 0;
  return (hv.size_allocated() - cardinality()) / (double) hv.size_allocated();
}

SV *OSPV_hvarray::FETCHp(char *key)
{
  int xx = index_of(key);
  if (xx == -1) {
    return 0;
  } else {
    return osperl::ospv_2sv(&hv[xx].hv);
  }
}

SV *OSPV_hvarray::STOREp(char *key, SV *value)
{
  int xx = index_of(key);
  if (xx == -1) {
    xx = hv.count();
    hv[hv.count()].hk.s(key, strlen(key)+1);
  }
  hv[xx].hv = value;
  if (GIMME_V == G_VOID) return 0;
  return osperl::ospv_2sv(&hv[xx].hv);
}

void OSPV_hvarray::DELETE(char *key)
{
  int xx = index_of(key);
  if (xx != -1) {
    hv[xx].hk.set_undef();
    hv[xx].hv.set_undef();
  }
}

void OSPV_hvarray::CLEAR()
{
  int cursor = 0;
  while ((cursor = first(cursor)) != -1) {
    hv[cursor].hk.set_undef();
    hv[cursor].hv.set_undef();
    cursor++;
  }
}

int OSPV_hvarray::EXISTS(char *key)
{ return index_of(key) != -1; }

int OSPV_hvarray::first(int start)
{
  int xx;
  for (xx=start; xx < hv.count(); xx++) {
    if (hv[xx].hk.valid()) return xx;
  }
  return -1;
}

struct hvarray_bridge : ossv_bridge {
  int cursor;
  hvarray_bridge(OSSV *, OSSVPV *);
};
hvarray_bridge::hvarray_bridge(OSSV *_sv, OSSVPV *_pv) : ossv_bridge(_sv,_pv), cursor(0)
{}

ossv_bridge *OSPV_hvarray::NEW_BRIDGE(OSSV *sv, OSSVPV *pv)
{ return new hvarray_bridge(sv,pv); }

SV *OSPV_hvarray::FIRST(ossv_bridge *vmg)
{
  hvarray_bridge *mg = (hvarray_bridge *) vmg;
  SV *out;
  mg->cursor = first(0);
  if (mg->cursor != -1) {
    out = osperl::hkey_2sv(&hv[mg->cursor].hk);
  } else {
    out = &sv_undef;
  }
  return out;
}

SV *OSPV_hvarray::NEXT(ossv_bridge *vmg)
{
  hvarray_bridge *mg = (hvarray_bridge *) vmg;
  SV *out;
  mg->cursor++;
  mg->cursor = first(mg->cursor);
  if (mg->cursor != -1) {
    out = osperl::hkey_2sv(&hv[mg->cursor].hk);
  } else {
    out = &sv_undef;
  }
  return out;
}

/*--------------------------------------------- HV os_dictionary */

XS(XS_ObjStore__HV__new_os_dictionary)
{
  dXSARGS;
  if (items != 3) croak("Usage: &$create('ObjStore::HV', $segment, $card)");
  {
    char *clname = SvPV(ST(0), na);
    os_segment *area = osperl::sv_2segment(ST(1));
    int card = (int)SvIV(ST(2));

    if (card < 0) croak("Negative cardinality");

    OSSVPV *pv = new(area, OSPV_hvdict::get_os_typespec()) OSPV_hvdict(card);
    pv->BLESS(clname);
    ST(0) = osperl::ospv_2sv(pv);
  }    
  XSRETURN(1);
}

OSPV_hvdict::OSPV_hvdict(os_unsigned_int32 card)
  : hv(card,
       os_dictionary::signal_dup_keys |
       os_collection::pick_from_empty_returns_null |
       os_dictionary::dont_maintain_cardinality)
{}

OSPV_hvdict::~OSPV_hvdict()
{
#ifdef DEBUG_MEM_OSSVPV
  warn("~OSPV_hvdict %x", this);
#endif
  CLEAR();
}

char *OSPV_hvdict::base_class()
{ return "ObjStore::HV"; }

int OSPV_hvdict::get_perl_type()
{ return SVt_PVHV; }

double OSPV_hvdict::cardinality()
{ return hv.cardinality(); }

double OSPV_hvdict::percent_unused()
{ return .30; }  //???

char *OSPV_hvdict::GETSTR(char *key)
{
  OSSV *ret = hv.pick(key);
  if (ret && ret->natural() == ossv_pv) {
    return (char*) ret->vptr;
  } else {
    croak("OSPV_hvdict::GETSTR(%s): not found", key);
  }
}

SV *OSPV_hvdict::FETCHp(char *key)
{
  OSSV *ret = hv.pick(key);
#ifdef DEBUG_HVDICT
  warn("OSPV_hvdict::FETCH %s => %s", key, ret? ret->as_pv() : "<0x0>");
#endif
  return osperl::ossv_2sv(ret);
}

SV *OSPV_hvdict::STOREp(char *key, SV *nval)
{
  os_segment *WHERE = os_segment::of(this);
  OSSV *ossv=0;
  int insert=0;

  if (!ossv) {
    ossv = (OSSV*) hv.pick(key);
    if (ossv) *ossv = nval;
    else insert=1;
  }
  if (!ossv) {
    ossv_bridge *mg = osperl::sv_2bridge(nval);
    if (mg) ossv = mg->force_ossv();
  }
  if (!ossv) {
    ossv = new(WHERE, OSSV::get_os_typespec()) OSSV(nval);
  }
  assert(ossv);
#ifdef DEBUG_HVDICT
  warn("OSPV_hvdict::INSERT(%s=%s)", key, ossv->as_pv());
#endif
  if (insert) {
    ossv = ossv->REF_inc();
    hv.insert(key, ossv);
  }

  if (GIMME_V == G_VOID) return 0;
  return osperl::ossv_2sv(ossv);
}

void OSPV_hvdict::DELETE(char *key)
{
  OSSV *val = hv.pick(key);
  hv.remove_value(key);
#ifdef DEBUG_HVDICT
  warn("OSPV_hvdict::DELETE(%s) deleting hash value 0x%x", key, val);
#endif
  if (val) val->REF_dec();   //XXX val==0 ?
}

void OSPV_hvdict::CLEAR()
{
  os_cursor cs(hv);
  while (cs.first()) {
    hkey *k1 = (hkey*) hv.retrieve_key(cs);
    OSSV *val = hv.pick(k1);
    hv.remove_value(*k1);
#ifdef DEBUG_HVDICT
    warn("OSPV_hvdict::CLEAR() deleting hash value 0x%x", val);
#endif
    if (val) val->REF_dec();
  }
}

int OSPV_hvdict::EXISTS(char *key)
{
  int out = hv.pick(key) != 0;
#ifdef DEBUG_HVDICT
  warn("OSPV_hvdict::exists %s => %d", key, out);
#endif
  return out;
}

struct hvdict_bridge : ossv_bridge {
  os_cursor *cs;
  hvdict_bridge(OSSV *, OSSVPV *);
  virtual ~hvdict_bridge();
};
hvdict_bridge::hvdict_bridge(OSSV *_sv, OSSVPV *_pv) : ossv_bridge(_sv,_pv), cs(0)
{}
hvdict_bridge::~hvdict_bridge()
{ if (cs) delete cs; }

ossv_bridge *OSPV_hvdict::NEW_BRIDGE(OSSV *_sv, OSSVPV *_pv)
{ return new hvdict_bridge(_sv,_pv); }

SV *OSPV_hvdict::FIRST(ossv_bridge *vmg)
{
  hvdict_bridge *mg = (hvdict_bridge *) vmg;
  if (!mg->cs) mg->cs = new os_cursor(hv);
  hkey *k1=0;
  if (mg->cs->first()) {
    k1 = (hkey*) hv.retrieve_key(*mg->cs);
    assert(k1);
  }
#ifdef DEBUG_HVDICT
  warn("OSPV_hvdict::FIRST => %s", k1? k1->as_pv() : "undef");
#endif
  return osperl::hkey_2sv(k1);
}

SV *OSPV_hvdict::NEXT(ossv_bridge *vmg)
{
  hvdict_bridge *mg = (hvdict_bridge *) vmg;
  assert(mg->cs);
  hkey *k1=0;
  if (mg->cs->next()) {
    k1 = (hkey*) hv.retrieve_key(*mg->cs);
    assert(k1);
  }
#ifdef DEBUG_HVDICT
  warn("OSPV_hvdict::NEXT => %s", k1? k1->as_pv() : "undef");
#endif
  return osperl::hkey_2sv(k1);
}

/*--------------------------------------------- Set splash_array */

XS(XS_ObjStore__Set__new_splash_array)
{
  dXSARGS;
  if (items != 3) croak("Usage: &$create('ObjStore::Set', $segment, $card)");
  {
    char *clname = SvPV(ST(0), na);
    os_segment *area = osperl::sv_2segment(ST(1));
    int card = (int)SvIV(ST(2));

    if (card < 0) {
      croak("Negative cardinality");
    } else if (card > 10000) {
      card = 10000;
      warn("Cardinality > 10000; try a more suitable representation");
    }

    OSSVPV *pv = new(area, OSPV_setarray::get_os_typespec()) OSPV_setarray(card);
    pv->BLESS(clname);
    ST(0) = osperl::ospv_2sv(pv);
  }    
  XSRETURN(1);
}

OSPV_setarray::OSPV_setarray(int size)
  : cv(size,8)
{
  //  warn("new OSPV_setarray(%d)", size);
}

OSPV_setarray::~OSPV_setarray()
{
#ifdef DEBUG_MEM_OSSVPV
  warn("~OSPV_setarray %x", this);
#endif
  CLEAR();
}

char *OSPV_setarray::base_class()
{ return "ObjStore::Set"; }

int OSPV_setarray::first(int start)
{
  int xx;
  for (xx=start; xx < cv.count(); xx++) {
    if (cv[xx].natural() != ossv_undef) return xx;
  }
  return -1;
}

double OSPV_setarray::cardinality()
{
  int good=0;
  for (int xx=0; xx < cv.count(); xx++) {
    if (cv[xx].natural() != ossv_undef) good++;
  }
  return good;
}

double OSPV_setarray::percent_unused()
{
  if (cv.size_allocated() <= 0) return 0;
  return (cv.size_allocated() - cardinality()) / (double) cv.size_allocated();
}

SV *OSPV_setarray::ADD(SV *nval)
{
  int spot=-1;
  // stupid, but definitely correct
  for (int xx=0; xx < cv.count(); xx++) {
    if (cv[xx].natural() != ossv_undef) continue;
    spot = xx;
    break;
  }
  if (spot == -1) spot = cv.count();
  cv[spot] = nval;
  if (cv[spot].natural() != ossv_obj)
    croak("OSPV_setarray::ADD(nval): sets can only contain objects");

  //  warn("added %s", cv[spot].as_pv());
  /*
  for (int zz=0; zz < cv.count(); zz++) {
    warn("cv[%d]: %d\n", zz, cv[zz].natural());
  }
  */
  if (GIMME_V == G_VOID) return 0;
  return osperl::ossv_2sv(&cv[spot]);
}

int OSPV_setarray::CONTAINS(SV *val)
{
  OSSVPV *pv = 0;
  ossv_bridge *mg = osperl::sv_2bridge(val);
  if (mg) pv = mg->ospv();
  if (!pv) croak("OSPV_setarray::CONTAINS(SV *val): must be persistent object");

  for (int xx=0; xx < cv.count(); xx++) {
    if (cv[xx] == pv) return 1;
  }
  return 0;
}

void OSPV_setarray::REMOVE(SV *nval)
{
  OSSVPV *pv = 0;
  ossv_bridge *mg = osperl::sv_2bridge(nval);
  if (mg) pv = mg->ospv();
  if (!pv) croak("OSPV_setarray::REMOVE(SV *val): must be persistent object");

  // stupid, but definitely correct
  for (int xx=0; xx < cv.count(); xx++) {
    if (cv[xx] == pv) {
      cv[xx].set_undef();
      return;
    }
  }
}

struct setarray_bridge : ossv_bridge {
  int cursor;
  setarray_bridge(OSSV *, OSSVPV *);
};
setarray_bridge::setarray_bridge(OSSV *_sv, OSSVPV *_pv) : ossv_bridge(_sv,_pv), cursor(0)
{}

ossv_bridge *OSPV_setarray::NEW_BRIDGE(OSSV *sv, OSSVPV *pv)
{ return new setarray_bridge(sv,pv); }

SV *OSPV_setarray::FIRST(ossv_bridge *vmg)
{
  setarray_bridge *mg = (setarray_bridge *) vmg;
  assert(mg);
  /*
  for (int xx=0; xx < cv.count(); xx++) {
    warn("cv[%d]: %d\n", xx, cv[xx].natural());
  }
  */
  mg->cursor=first(0);
  //  warn("FIRST: cursor = %d", mg->cursor);
  if (mg->cursor != -1) {
    return osperl::ospv_2sv((OSSVPV*) cv[mg->cursor].vptr);
  } else {
    return &sv_undef;
  }
}

SV *OSPV_setarray::NEXT(ossv_bridge *vmg)
{
  setarray_bridge *mg = (setarray_bridge *) vmg;
  assert(mg);
  mg->cursor++;
  mg->cursor = first(mg->cursor);
  //  warn("NEXT: cursor = %d", mg->cursor);
  if (mg->cursor != -1) {
    return osperl::ospv_2sv((OSSVPV*) cv[mg->cursor].vptr);
  } else {
    return &sv_undef;
  }
}

void OSPV_setarray::CLEAR()
{
  for (int xx=0; xx < cv.count(); xx++) { cv[xx].set_undef(); }
}

/*--------------------------------------------- Set os_set */

XS(XS_ObjStore__Set__new_os_set)
{
  dXSARGS;
  if (items != 3) croak("Usage: &$create('ObjStore::Set', $segment, $card)");
  {
    char *clname = SvPV(ST(0), na);
    os_segment *area = osperl::sv_2segment(ST(1));
    int card = (int)SvIV(ST(2));

    if (card < 0) croak("Negative cardinality");

    OSSVPV *pv = new(area, OSPV_sethash::get_os_typespec()) OSPV_sethash(card);
    pv->BLESS(clname);
    ST(0) = osperl::ospv_2sv(pv);
  }    
  XSRETURN(1);
}

OSPV_sethash::OSPV_sethash(os_unsigned_int32 size)
  : set(size)
{
  //  warn("new OSPV_sethash(%d)", size);
}

OSPV_sethash::~OSPV_sethash()
{
#ifdef DEBUG_MEM_OSSVPV
  warn("~OSPV_sethash %x", this);
#endif
  CLEAR();
}

char *OSPV_sethash::base_class()
{ return "ObjStore::Set"; }

double OSPV_sethash::cardinality()
{ return set.cardinality(); }

double OSPV_sethash::percent_unused()
{ return .30; }  //???

SV *OSPV_sethash::ADD(SV *nval)
{
  OSSVPV *ospv=0;

  ossv_bridge *mg = osperl::sv_2bridge(nval);
  if (mg) {
    ospv = mg->ospv();
    if (ospv) ospv->REF_inc();
  }

  if (!ospv) {
    ENTER ;
    SAVETMPS ;
    ossv_bridge *mg = osperl::force_sv_2bridge(os_segment::of(this), nval);
    ospv = mg->ospv();
    if (!ospv) croak("OSPV_sethash::ADD(SV*): cannot add non-object");
    ospv->REF_inc();
    FREETMPS ;
    LEAVE ;
  }

  set.insert(ospv);
  if (GIMME_V == G_VOID) return 0;
  return osperl::ospv_2sv(ospv);
}

int OSPV_sethash::CONTAINS(SV *nval)
{
  OSSVPV *ospv=0;
  ossv_bridge *mg = osperl::sv_2bridge(nval);
  if (mg) ospv = mg->ospv();
  if (!ospv) croak("OSPV_sethash::CONTAINS(SV *nval): cannot test non-object");
  return set.contains(ospv);
}

void OSPV_sethash::REMOVE(SV *nval)
{
  OSSVPV *ospv=0;
  ossv_bridge *mg = osperl::sv_2bridge(nval);
  if (mg) ospv = mg->ospv();
  if (!ospv) croak("OSPV_sethash::REMOVE(SV *nval): cannot remove non-object");
  if (set.remove(ospv)) ospv->REF_dec();
}

struct sethash_bridge : ossv_bridge {
  os_cursor *cs;
  sethash_bridge(OSSV *, OSSVPV *);
};
sethash_bridge::sethash_bridge(OSSV *_sv, OSSVPV *_pv) : ossv_bridge(_sv,_pv), cs(0)
{}

ossv_bridge *OSPV_sethash::NEW_BRIDGE(OSSV *sv, OSSVPV *pv)
{ return new sethash_bridge(sv,pv); }

SV *OSPV_sethash::FIRST(ossv_bridge *vmg)
{
  sethash_bridge *mg = (sethash_bridge *) vmg;
  assert(mg);
  if (!mg->cs) mg->cs = new os_cursor(set);
  return osperl::ospv_2sv( (OSSVPV*) mg->cs->first());
}

SV *OSPV_sethash::NEXT(ossv_bridge *vmg)
{
  sethash_bridge *mg = (sethash_bridge *) vmg;
  assert(mg);
  assert(mg->cursor);
  return osperl::ospv_2sv( (OSSVPV*) mg->cs->next());
}

void OSPV_sethash::CLEAR()
{
  while (!set.empty()) {
    OSSVPV *pv = (OSSVPV*) set.pick();
    set.remove(pv);
    pv->REF_dec();
  }
}

MODULE = ObjStore::GENERIC	PACKAGE = ObjStore::GENERIC

BOOT:
  SV *rep;
  os_collection::set_thread_locking(0);
  os_index_key(hkey, hkey::rank, hkey::hash);
  // AV
  HV *avrep = perl_get_hv("ObjStore::AV::REP", TRUE);
  rep = (SV*) newXS(0, XS_ObjStore__AV__new_splash_array, file);
  sv_setpv(rep, "$$$");
  rep = newRV(rep);
  hv_store(avrep, "splash_array", strlen("splash_array"), rep, 0);
  // HV
  HV *hvrep = perl_get_hv("ObjStore::HV::REP", TRUE);
  rep = (SV*) newXS(0, XS_ObjStore__HV__new_splash_array, file);
  sv_setpv(rep, "$$$");
  rep = newRV(rep);
  hv_store(hvrep, "splash_array", strlen("splash_array"), rep, 0);
  rep = (SV*) newXS(0, XS_ObjStore__HV__new_os_dictionary, file);
  sv_setpv(rep, "$$$");
  rep = newRV(rep);
  hv_store(hvrep, "os_dictionary", strlen("os_dictionary"), rep, 0);
  // Set
  HV *setrep = perl_get_hv("ObjStore::Set::REP", TRUE);
  rep = (SV*) newXS(0, XS_ObjStore__Set__new_splash_array, file);
  sv_setpv(rep, "$$$");
  rep = newRV(rep);
  hv_store(setrep, "splash_array", strlen("splash_array"), rep, 0);
  rep = (SV*) newXS(0, XS_ObjStore__Set__new_os_set, file);
  sv_setpv(rep, "$$$");
  rep = newRV(rep);
  hv_store(setrep, "os_set", strlen("os_set"), rep, 0);


MODULE = ObjStore::GENERIC	PACKAGE = ObjStore::AV

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

MODULE = ObjStore::GENERIC	PACKAGE = ObjStore::HV

SV *
OSSVPV::FETCH(key)
	char *key;
	CODE:
	ST(0) = THIS->FETCHp(key);

RAW_STRING *
OSSVPV::_at(key)
	char *key;
	CODE:
	char *CLASS = "ObjStore::RAW_STRING";
	RETVAL = THIS->GETSTR(key);
	OUTPUT:
	RETVAL

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
	ST(0) = THIS->FIRST( THIS_bridge );

SV *
OSSVPV::NEXTKEY(ign)
	char *ign;
	CODE:
	ST(0) = THIS->NEXT( THIS_bridge );

void
OSSVPV::CLEAR()
	CODE:
	THIS->CLEAR();

MODULE = ObjStore::GENERIC	PACKAGE = ObjStore::Set

void
OSSVPV::add(...)
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
OSSVPV::rm(nval)
	SV *nval;
	CODE:
	THIS->REMOVE(nval);

SV *
OSSVPV::first()
	CODE:
	ST(0) = THIS->FIRST( THIS_bridge );

SV *
OSSVPV::next()
	CODE:
	ST(0) = THIS->NEXT( THIS_bridge );

