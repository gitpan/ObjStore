/*
Copyright (c) 1997 Joshua Nathaniel Pritikin.  All rights reserved.
This package is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

1. Gives XS interfaces tied arrays, tied hashes, and sets.
2. Provides a few implementations.
*/

#include <assert.h>
#include "osperl.hh"
#include "GENERIC.hh"

//#define DEBUG_HVDICT 1
//#define DEBUG_AVARRAY 1

/*--------------------------------------------- stubs */

SV *OSSVPV::FIRST(ossv_bridge*) { croak("OSSVPV(0x%x)->FIRST",this); return 0; }
SV *OSSVPV::NEXT(ossv_bridge*) { croak("OSSVPV(0x%x)->NEXT",this); return 0; }
void OSSVPV::CLEAR() { croak("OSSVPV(0x%x)->CLEAR",this); }

// hash
SV *OSSVPV::FETCHp(char *) { croak("OSSVPV(0x%x)->FETCHp",this); return 0; }
SV *OSSVPV::STOREp(char *, SV *) { croak("OSSVPV(0x%x)->STOREp",this); return 0; }
void OSSVPV::DELETE(char *) { croak("OSSVPV(0x%x)->DELETE",this); }
int OSSVPV::EXISTS(char *) { croak("OSSVPV(0x%x)->EXISTS",this); return 0; }

// set
SV *OSSVPV::add(SV *) { croak("OSSVPV(0x%x)->add",this); return 0; }
int OSSVPV::contains(SV *) { croak("OSSVPV(0x%x)->contains",this); return 0; }
void OSSVPV::rm(SV *) { croak("OSSVPV(0x%x)->rm",this); }

// array (depreciated)
SV *OSSVPV::FETCHi(int) { croak("OSSVPV(0x%x)->FETCHi", this); return 0; }
SV *OSSVPV::STOREi(int, SV *) { croak("OSSVPV(0x%x)->STOREi",this); return 0; }
int OSSVPV::_LENGTH() {croak("OSSVPV(0x%x)->_LENGTH",this); return 0; }

static void install_rep(HV *hv, char *name, XS_t mk) //move to osperl XXX
{
  SV *rep = (SV*) newXS(0, mk, __FILE__);
  sv_setpv(rep, "$$$");
  hv_store(hv, name, strlen(name), newRV(rep), 0);
}

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
    pv->_bless(clname);
    ST(0) = osperl::ospv_2sv(pv);
  }    
  XSRETURN(1);
}

OSPV_avarray::OSPV_avarray(int sz)
  : av(sz,8)
{}

OSPV_avarray::~OSPV_avarray()
{ CLEAR(); }

void OSPV_avarray::_boot(HV *hv)
{ install_rep(hv, "splash_array", XS_ObjStore__AV__new_splash_array); }

double OSPV_avarray::_percent_filled()
{
  I32 used=0;
  for (int xx=0; xx < av.size_allocated(); xx++) { used += av[xx].is_set(); }
  return used / (double) av.size_allocated();
}

char *OSPV_avarray::base_class()
{ return "ObjStore::AV"; }

int OSPV_avarray::get_perl_type()
{ return SVt_PVAV; }

SV *OSPV_avarray::FETCHi(int xx)
{
#if DEBUG_AVARRAY
  warn("OSPV_avarray(0x%x)->FETCHi(%d)", this, xx);
#endif
  return osperl::ossv_2sv(&av[xx]);
}

SV *OSPV_avarray::STOREi(int xx, SV *value)
{
#if DEBUG_AVARRAY
  warn("OSPV_avarray(0x%x)->STOREi(%d)", this, xx);
#endif
  av[xx] = value;
  if (GIMME_V == G_VOID) return 0;
  return osperl::ossv_2sv(&av[xx]);
}

int OSPV_avarray::_LENGTH()
{ return av.count(); }

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
    pv->_bless(clname);
    ST(0) = osperl::ospv_2sv(pv);
  }    
  XSRETURN(1);
}

void OSPV_hvarray::_boot(HV *hv)
{ install_rep(hv, "splash_array", XS_ObjStore__HV__new_splash_array); }

OSPV_hvarray::OSPV_hvarray(int sz)
  : hv(sz,8)
{}

OSPV_hvarray::~OSPV_hvarray()
{ CLEAR(); }

double OSPV_hvarray::_percent_filled()
{
  I32 used=0;
  for (int xx=0; xx < hv.size_allocated(); xx++) { used += hv[xx].hk.valid(); }
  return used / (double) hv.size_allocated();
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

SV *OSPV_hvarray::FETCHp(char *key)
{
  int xx = index_of(key);
  if (xx == -1) {
    return 0;
  } else {
    return osperl::ossv_2sv(&hv[xx].hv);
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
  return osperl::ossv_2sv(&hv[xx].hv);
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
  hvarray_bridge(OSSVPV *);
};
hvarray_bridge::hvarray_bridge(OSSVPV *_pv) : ossv_bridge(_pv), cursor(0)
{}

ossv_bridge *OSPV_hvarray::_new_bridge(OSSVPV *pv)
{ return new hvarray_bridge(pv); }

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
    pv->_bless(clname);
    ST(0) = osperl::ospv_2sv(pv);
  }    
  XSRETURN(1);
}

void OSPV_setarray::_boot(HV *hv)
{ install_rep(hv, "splash_array", XS_ObjStore__Set__new_splash_array); }

OSPV_setarray::OSPV_setarray(int size)
  : cv(size,8)
{
  //  warn("new OSPV_setarray(%d)", size);
}

OSPV_setarray::~OSPV_setarray()
{ CLEAR(); }

double OSPV_setarray::_percent_filled()
{
  I32 used=0;
  for (int xx=0; xx < cv.size_allocated(); xx++) { used += cv[xx].is_set(); }
  return used / (double) cv.size_allocated();
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

SV *OSPV_setarray::add(SV *nval)
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
    croak("OSPV_setarray::add(nval): sets can only contain objects");

  //  warn("added %s", cv[spot].as_pv());
  /*
  for (int zz=0; zz < cv.count(); zz++) {
    warn("cv[%d]: %d\n", zz, cv[zz].natural());
  }
  */
  if (GIMME_V == G_VOID) return 0;
  return osperl::ossv_2sv(&cv[spot]);
}

int OSPV_setarray::contains(SV *val)
{
  OSSVPV *pv = 0;
  ossv_bridge *mg = osperl::sv_2bridge(val);
  if (mg) pv = mg->ospv();
  if (!pv) croak("OSPV_setarray::contains(SV *val): must be persistent object");

  for (int xx=0; xx < cv.count(); xx++) {
    if (cv[xx] == pv) return 1;
  }
  return 0;
}

void OSPV_setarray::rm(SV *nval)
{
  OSSVPV *pv = 0;
  ossv_bridge *mg = osperl::sv_2bridge(nval);
  if (mg) pv = mg->ospv();
  if (!pv) croak("OSPV_setarray::rm(SV *val): must be persistent object");

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
  setarray_bridge(OSSVPV *);
};
setarray_bridge::setarray_bridge(OSSVPV *_pv) : ossv_bridge(_pv), cursor(0)
{}

ossv_bridge *OSPV_setarray::_new_bridge(OSSVPV *pv)
{ return new setarray_bridge(pv); }

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
    pv->_bless(clname);
    ST(0) = osperl::ospv_2sv(pv);
  }    
  XSRETURN(1);
}

void OSPV_hvdict::_boot(HV *hv)
{ install_rep(hv, "os_dictionary", XS_ObjStore__HV__new_os_dictionary); }

OSPV_hvdict::OSPV_hvdict(os_unsigned_int32 card)
  : hv(card,
       os_dictionary::signal_dup_keys |
       os_collection::pick_from_empty_returns_null |
       os_dictionary::dont_maintain_cardinality)
{}

OSPV_hvdict::~OSPV_hvdict()
{ CLEAR(); }

char *OSPV_hvdict::base_class()
{ return "ObjStore::HV"; }

int OSPV_hvdict::get_perl_type()
{ return SVt_PVHV; }

char *OSPV_hvdict::_get_raw_string(char *key)
{
  OSSV *ret = hv.pick(key);
  if (ret && ret->natural() == ossv_pv) {
    return (char*) ret->vptr;
  } else {
    croak("OSPV_hvdict::_get_raw_string(%s): not found", key);
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
  OSSV *ossv = (OSSV*) hv.pick(key);
  if (ossv) {
    *ossv = nval;
  } else {
    ossv = osperl::plant_sv(os_segment::of(this), nval);
    hv.insert(key, ossv);
  }
#ifdef DEBUG_HVDICT
  warn("OSPV_hvdict::INSERT(%s=%s)", key, ossv->as_pv());
#endif

  if (GIMME_V == G_VOID) return 0;
  return osperl::ossv_2sv(ossv);
}

void OSPV_hvdict::DELETE(char *key)
{
  OSSV *val = hv.pick(key);
  assert(val);
  hv.remove_value(key);
#ifdef DEBUG_HVDICT
  warn("OSPV_hvdict::DELETE(%s) deleting hash value 0x%x", key, val);
#endif
  delete val;
}

void OSPV_hvdict::CLEAR()
{
  os_cursor cs(hv);
  while (cs.first()) {
    hkey *k1 = (hkey*) hv.retrieve_key(cs);
    OSSV *val = hv.pick(k1);
    assert(val);
    hv.remove_value(*k1);
#ifdef DEBUG_HVDICT
    warn("OSPV_hvdict::CLEAR() deleting hash value 0x%x", val);
#endif
    delete val;
  }
}

int OSPV_hvdict::EXISTS(char *key)
{
  int out = hv.pick(key) != 0;
#ifdef DEBUG_HVDICT
  warn("OSPV_hvdict::EXISTS %s => %d", key, out);
#endif
  return out;
}

struct hvdict_bridge : ossv_bridge {
  os_cursor *cs;
  hvdict_bridge(OSSVPV *);
  virtual ~hvdict_bridge();
};
hvdict_bridge::hvdict_bridge(OSSVPV *_pv) : ossv_bridge(_pv), cs(0)
{}
hvdict_bridge::~hvdict_bridge()
{ if (cs) delete cs; }

ossv_bridge *OSPV_hvdict::_new_bridge(OSSVPV *_pv)
{ return new hvdict_bridge(_pv); }

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

OSPV_Cursor *OSPV_hvdict::new_cursor(os_segment *seg)
{
  //  return new(seg, OSPV_hvdict_cs::get_os_typespec()) OSPV_hvdict_cs(this);
  return 0;
}

OSPV_hvdict_cs::OSPV_hvdict_cs(OSPV_hvdict *_at)
  : at(_at), cs(_at->hv)
{ at->REF_inc(); }

OSPV_hvdict_cs::~OSPV_hvdict_cs()
{ at->REF_dec(); }

SV *OSPV_hvdict_cs::focus()
{ return osperl::ospv_2sv(at); }

int OSPV_hvdict_cs::more()
{ return cs.more(); }

void OSPV_hvdict_cs::first()
{
  OSSV *ossv = (OSSV*) cs.first();
  osperl::push_key_ossv((hkey*) (ossv? at->hv.retrieve_key(cs) : 0), ossv);
}

void OSPV_hvdict_cs::next()
{
  OSSV *ossv = (OSSV*) cs.next();
  osperl::push_key_ossv((hkey*) (ossv? at->hv.retrieve_key(cs) : 0), ossv);
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
    pv->_bless(clname);
    ST(0) = osperl::ospv_2sv(pv);
  }    
  XSRETURN(1);
}

void OSPV_sethash::_boot(HV *hv)
{ install_rep(hv, "os_set", XS_ObjStore__Set__new_os_set); }

OSPV_sethash::OSPV_sethash(os_unsigned_int32 size)
  : set(size)
{
  //  warn("new OSPV_sethash(%d)", size);
}

OSPV_sethash::~OSPV_sethash()
{ CLEAR(); }

char *OSPV_sethash::base_class()
{ return "ObjStore::Set"; }

SV *OSPV_sethash::add(SV *nval)
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
    if (!ospv) croak("OSPV_sethash::add(SV*): cannot add non-object");
    ospv->REF_inc();
    FREETMPS ;
    LEAVE ;
  }

  set.insert(ospv);
  if (GIMME_V == G_VOID) return 0;
  return osperl::ospv_2sv(ospv);
}

int OSPV_sethash::contains(SV *nval)
{
  OSSVPV *ospv=0;
  ossv_bridge *mg = osperl::sv_2bridge(nval);
  if (mg) ospv = mg->ospv();
  if (!ospv) croak("OSPV_sethash::contains(SV *nval): cannot test non-object");
  return set.contains(ospv);
}

void OSPV_sethash::rm(SV *nval)
{
  OSSVPV *ospv=0;
  ossv_bridge *mg = osperl::sv_2bridge(nval);
  if (mg) ospv = mg->ospv();
  if (!ospv) croak("OSPV_sethash::rm(SV *nval): cannot remove non-object");
  if (set.remove(ospv)) ospv->REF_dec();
}

struct sethash_bridge : ossv_bridge {
  os_cursor *cs;
  sethash_bridge(OSSVPV *);
};
sethash_bridge::sethash_bridge(OSSVPV *_pv) : ossv_bridge(_pv), cs(0)
{}

ossv_bridge *OSPV_sethash::_new_bridge(OSSVPV *pv)
{ return new sethash_bridge(pv); }

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
  assert(mg->cs);
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

OSPV_Cursor *OSPV_sethash::new_cursor(os_segment *seg)
{
  //  return new(seg, OSPV_sethash_cs::get_os_typespec()) OSPV_sethash_cs(this);
  return 0;
}

OSPV_sethash_cs::OSPV_sethash_cs(OSPV_sethash *_at)
  : at(_at), cs(_at->set)
{ at->REF_inc(); }

OSPV_sethash_cs::~OSPV_sethash_cs()
{ at->REF_dec(); }

SV *OSPV_sethash_cs::focus()
{ return osperl::ospv_2sv(at); }

int OSPV_sethash_cs::more()
{ return cs.more(); }

void OSPV_sethash_cs::first()
{ osperl::push_ospv((OSSVPV*) cs.first()); }

void OSPV_sethash_cs::next()
{ osperl::push_ospv((OSSVPV*) cs.next()); }


MODULE = ObjStore::GENERIC	PACKAGE = ObjStore::GENERIC

BOOT:
  SV *rep;
  char *tag;
  os_collection::set_thread_locking(0);
  os_index_key(hkey, hkey::rank, hkey::hash);
  // AV
  HV *avrep = perl_get_hv("ObjStore::AV::REP", TRUE);
  OSPV_avarray::_boot(avrep);
  // HV
  HV *hvrep = perl_get_hv("ObjStore::HV::REP", TRUE);
  OSPV_hvarray::_boot(hvrep);
  OSPV_hvdict::_boot(hvrep);
  // Set
  HV *setrep = perl_get_hv("ObjStore::Set::REP", TRUE);
  OSPV_setarray::_boot(setrep);
  OSPV_sethash::_boot(setrep);

