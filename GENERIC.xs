/*-*-c++-*-
Copyright (c) 1997 Joshua Nathaniel Pritikin.  All rights reserved.
This package is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.
*/

#include "osperl.h"
#include "GENERIC.h"

static const char *file = __FILE__;

// static method?
static SV *hkey_2sv(hkey *hk)
{
  // ignore zero termination for easy coersion to numbers
  if (!hk || !hk->pv || hk->len < 2) return &sv_undef;
  return sv_2mortal(newSVpv(hk->pv, hk->len-1));
}

// move pushes to ...?
static void push_index_ossv(int xx, OSSV *hv)
{
  if (!hv) return;
  assert(hv);
  dOSP ;
  SV *sv[2] = {sv_2mortal(newSViv(xx)), osp->ossv_2sv(hv)};
  dSP;
  EXTEND(SP, 2);
  PUSHs(sv[0]);
  PUSHs(sv[1]);
  PUTBACK;
}

static void push_hkey_ossv(hkey *hk, OSSV *hv)
{
  if (!hk && !hv) return;
  assert(hk && hv);
  dOSP ;
  SV *sv[2] = {hkey_2sv(hk), osp->ossv_2sv(hv)};
  dSP;
  EXTEND(SP, 2);
  PUSHs(sv[0]);
  PUSHs(sv[1]);
  PUTBACK;
}

static void push_sv_ossv(SV *hk, OSSV *hv)
{
  dOSP ;
  SV *sv[2] = {hk, osp->ossv_2sv(hv)};
  dSP;
  EXTEND(SP, 2);
  PUSHs(sv[0]);
  PUSHs(sv[1]);
  PUTBACK;
}

/*--------------------------------------------- */
/*--------------------------------------------- hkey */

hkey::hkey() : pv(0)
{ }
hkey::hkey(const hkey &k1) : pv(0)
{ this->operator=(k1); }
hkey::hkey(const char *s1) : pv(0)
{ this->s(s1, strlen(s1)+1); }
hkey::hkey(const char *s1, os_unsigned_int32 nlen) : pv(0)
{ this->s(s1, nlen); }
hkey::~hkey()
{ set_undef(); }

int hkey::valid()
{ return pv != 0; }

void hkey::set_undef()
{
  len=0;
  if (pv) delete [] pv;
  pv=0;
}

hkey *hkey::operator=(const hkey &k1)
{
  set_undef();
  len = k1.len;
  if (len) {
    pv = new(os_segment::of(this), os_typespec::get_char(), len) char[len];
    memcpy(pv, k1.pv, len);
  }
  return this;
}

hkey *hkey::operator=(const char *k1)
{
  this->s(k1, strlen(k1)+1);
  return this;
}

void hkey::s(const char *k1, os_unsigned_int32 nlen)
{
  set_undef();
  len = nlen;
  if (len) {
    pv = new(os_segment::of(this), os_typespec::get_char(), len) char[len];
    memcpy(pv, k1, len);
  }
}

os_unsigned_int32 hkey::hash(const void *v1)
{
  const hkey *s1 = (hkey*)v1;
  if (s1->len > 8) {
    return ((os_int32*) s1->pv)[0] ^ ((os_int32*) s1->pv)[1] ^ s1->len;
  } else if (!s1->pv || s1->len == 0) {
    return 0;
  } else {
    os_int32 ret=s1->len;
    for (int xx=0; xx < s1->len; xx++) {
      ret = ret ^ (s1->pv[xx] << (8*xx));
      if (xx == 3) break;
    }
    return ret;
  }
}

int hkey::rank(const void *v1, const void *v2)
{
  const hkey *s1 = (hkey*)v1;
  const hkey *s2 = (hkey*)v2;
  if (s1->pv == 0 || s2->pv == 0) {
    if (s1->pv) return os_collection::GT;
    if (s2->pv) return os_collection::LT;
    return os_collection::EQ;
  } else {
    return strcmp(s1->pv, s2->pv);
  }
}

/*--------------------------------------------- */
/*--------------------------------------------- HV splash array */

hent *hent::operator=(int zero)
{ assert(zero==0); hk.set_undef(); hv.set_undef(); return this; }

hent *hent::operator=(const hent &nval)
{
  hk.operator=(nval.hk); hv.operator=( (OSSV&) nval.hv);
  return this;
}

XS(XS_ObjStore__HV__new_splash_array)
{
  dXSARGS;
  if (items != 3) croak("Usage: &$create('ObjStore::HV', $segment, $card)");
  SP -= items;

  dOSP ;
  char *clsv = SvPV(ST(0), na);
  os_segment *area = osp->sv_2segment(ST(1));
  int card = (int)SvIV(ST(2));
  PUTBACK;
  
  if (card <= 0) {
    croak("Non-positive cardinality");
  } else if (card > 1000) {
    card = 1000;
    warn("Cardinality > 1000; try a more suitable representation");
  }
  
  OSSVPV *pv = new(area, OSPV_hvarray::get_os_typespec()) OSPV_hvarray(card);
  pv->_bless(clsv);
  osp->push_ospv(pv);
}

void OSPV_hvarray::_boot(HV *hv)
{ install_rep(hv, file, "splash_array", XS_ObjStore__HV__new_splash_array); }

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

int OSPV_hvarray::_count()
{ return hv.count(); }

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
    dOSP ;
    return osp->ossv_2sv(&hv[xx].hv);
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
  dOSP ;
  return osp->ossv_2sv(&hv[xx].hv);
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
    out = hkey_2sv(&hv[mg->cursor].hk);
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
    out = hkey_2sv(&hv[mg->cursor].hk);
  } else {
    out = &sv_undef;
  }
  return out;
}

OSPV_Cursor *OSPV_hvarray::new_cursor(os_segment *seg)
{ return new(seg, OSPV_hvarray_cs::get_os_typespec()) OSPV_hvarray_cs(this); }

OSPV_hvarray_cs::OSPV_hvarray_cs(OSPV_hvarray *_at)
  : OSPV_Cursor(_at)
{ seek_pole(0); }

void OSPV_hvarray_cs::seek_pole(int end)
{
  OSPV_hvarray *pv = (OSPV_hvarray*)focus();
  if (!end) cs = 0;
  else cs = pv->hv.count()-1;
}

void OSPV_hvarray_cs::at()
{
  OSPV_hvarray *pv = (OSPV_hvarray*)focus();
  int cnt = pv->hv.count();
  if (cs >= 0 && cs < cnt) push_hkey_ossv(&pv->hv[cs].hk, &pv->hv[cs].hv);
}

void OSPV_hvarray_cs::next()
{
  OSPV_hvarray *pv = (OSPV_hvarray*)focus();
  int cnt = pv->hv.count();
  at();
  if (cs < cnt) ++ cs;
  if (cs < cnt) { cs = pv->first(cs); if (cs==-1) cs = cnt; }
}

/*--------------------------------------------- */
/*--------------------------------------------- Set splash_array */

XS(XS_ObjStore__Set__new_splash_array)
{
  dXSARGS;
  if (items != 3) croak("Usage: &$create('ObjStore::Set', $segment, $card)");
  SP -= items;

  dOSP ;
  char *clsv = SvPV(ST(0),na);
  os_segment *area = osp->sv_2segment(ST(1));
  int card = (int)SvIV(ST(2));
  PUTBACK;

  if (card <= 0) {
    croak("Non-positive cardinality");
  } else if (card > 1000) {
    card = 1000;
    warn("Cardinality > 1000; try a more suitable representation");
  }

  OSSVPV *pv = new(area, OSPV_setarray::get_os_typespec()) OSPV_setarray(card);
  pv->_bless(clsv);
  osp->push_ospv(pv);
}

void OSPV_setarray::_boot(HV *hv)
{ install_rep(hv, file, "splash_array", XS_ObjStore__Set__new_splash_array); }

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

int OSPV_setarray::_count()
{ return cv.count(); }

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

void OSPV_setarray::add(SV *nval)
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
}

int OSPV_setarray::contains(SV *val)
{
  dOSP ;
  OSSVPV *pv = 0;
  ossv_bridge *mg = osp->sv_2bridge(val, 0);
  if (mg) pv = mg->ospv();
  if (!pv) croak("OSPV_setarray::contains(SV *val): must be persistent object");

  for (int xx=0; xx < cv.count(); xx++) {
    if (cv[xx] == pv) return 1;
  }
  return 0;
}

void OSPV_setarray::rm(SV *nval)
{
  dOSP ;
  OSSVPV *pv = 0;
  ossv_bridge *mg = osp->sv_2bridge(nval, 0);
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
    dOSP ;
    return osp->ospv_2sv((OSSVPV*) cv[mg->cursor].vptr);
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
    dOSP ;
    return osp->ospv_2sv((OSSVPV*) cv[mg->cursor].vptr);
  } else {
    return &sv_undef;
  }
}

void OSPV_setarray::CLEAR()
{
  for (int xx=0; xx < cv.count(); xx++) { cv[xx].set_undef(); }
}

OSPV_Cursor *OSPV_setarray::new_cursor(os_segment *seg)
{ return new(seg, OSPV_setarray_cs::get_os_typespec()) OSPV_setarray_cs(this); }

OSPV_setarray_cs::OSPV_setarray_cs(OSPV_setarray *_at)
  : OSPV_Cursor(_at)
{ seek_pole(0); }

void OSPV_setarray_cs::seek_pole(int end)
{
  OSPV_setarray *pv = (OSPV_setarray*)focus();
  if (!end) cs = 0;
  else cs = pv->cv.count()-1;
}

void OSPV_setarray_cs::at()
{
  OSPV_setarray *pv = (OSPV_setarray*)focus();
  int cnt = pv->cv.count();
  if (cs >= 0 && cs < cnt) {
    dOSP ;
    osp->push_ospv((OSSVPV*) pv->cv[cs].vptr);
  }
}

void OSPV_setarray_cs::next()
{
  OSPV_setarray *pv = (OSPV_setarray*)focus();
  int cnt = pv->cv.count();
  at();
  if (cs < cnt) ++cs;
  if (cs < cnt) { cs = pv->first(cs); if (cs==-1) cs = cnt; }
}

/*--------------------------------------------- */
/*--------------------------------------------- HV os_dictionary */

XS(XS_ObjStore__HV__new_os_dictionary)
{
  dXSARGS;
  if (items != 3) croak("Usage: &$create('ObjStore::HV', $segment, $card)");
  SP -= items;

  dOSP ;
  char *clsv = SvPV(ST(0), na);
  os_segment *area = osp->sv_2segment(ST(1));
  int card = (int)SvIV(ST(2));
  PUTBACK;
  
  if (card <= 0) croak("Non-positive cardinality");
  
  OSSVPV *pv = new(area, OSPV_hvdict::get_os_typespec()) OSPV_hvdict(card);
  pv->_bless(clsv);
  osp->push_ospv(pv);
}

void OSPV_hvdict::_boot(HV *hv)
{ install_rep(hv, file, "os_dictionary", XS_ObjStore__HV__new_os_dictionary); }

OSPV_hvdict::OSPV_hvdict(os_unsigned_int32 card)
  : hv(card,
       os_dictionary::signal_dup_keys |
       os_collection::pick_from_empty_returns_null |
       os_dictionary::dont_maintain_cardinality)
{}

OSPV_hvdict::~OSPV_hvdict()
{ CLEAR(); }

int OSPV_hvdict::_count()
{ return hv.cardinality(); }

char *OSPV_hvdict::base_class()
{ return "ObjStore::HV"; }

int OSPV_hvdict::get_perl_type()
{ return SVt_PVHV; }

RAW_STRING *OSPV_hvdict::_get_raw_string(char *key)
{
  OSSV *ret = hv.pick(key);
  if (ret) {
    return ret->get_raw_string();
  } else {
    croak("OSPV_hvdict::_get_raw_string(%s): not found", key);
  }
}

SV *OSPV_hvdict::FETCHp(char *key)
{
  OSSV *ret = hv.pick(key);
  DEBUG_hash(warn("OSPV_hvdict::FETCH %s => %s", key, ret? ret->as_pv() : "<0x0>"));
  dOSP ;
  return osp->ossv_2sv(ret);
}

SV *OSPV_hvdict::STOREp(char *key, SV *nval)
{
  OSSV *ossv = (OSSV*) hv.pick(key);
  dOSP ;
  if (ossv) {
    *ossv = nval;
  } else {
    ossv = osp->plant_sv(os_segment::of(this), nval);
    hv.insert(key, ossv);
  }
  DEBUG_hash(warn("OSPV_hvdict::INSERT(%s=%s)", key, ossv->as_pv()));

  if (GIMME_V == G_VOID) return 0;
  return osp->ossv_2sv(ossv);
}

void OSPV_hvdict::DELETE(char *key)
{
  OSSV *val = hv.pick(key);
  if (!val) return;
  hv.remove_value(key);
  DEBUG_hash(warn("OSPV_hvdict::DELETE(%s) deleting hash value 0x%x", key, val));
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
    DEBUG_hash(warn("OSPV_hvdict::CLEAR() deleting hash value 0x%x", val));
    delete val;
  }
}

int OSPV_hvdict::EXISTS(char *key)
{
  int out = hv.pick(key) != 0;
  DEBUG_hash(warn("OSPV_hvdict::EXISTS %s => %d", key, out));
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
  DEBUG_hash(warn("OSPV_hvdict::FIRST => %s", k1? k1->pv : "undef"));
  return hkey_2sv(k1);
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
  DEBUG_hash(warn("OSPV_hvdict::NEXT => %s", k1? k1->pv : "undef"));
  return hkey_2sv(k1);
}

OSPV_Cursor *OSPV_hvdict::new_cursor(os_segment *seg)
{ return new(seg, OSPV_hvdict_cs::get_os_typespec()) OSPV_hvdict_cs(this); }

OSPV_hvdict_cs::OSPV_hvdict_cs(OSPV_hvdict *_at)
  : OSPV_Cursor(_at), cs(_at->hv)
{ seek_pole(0); }

void OSPV_hvdict_cs::seek_pole(int end)
{ reset_2pole = end; }

void OSPV_hvdict_cs::at()
{
  if (reset_2pole != -1) {
    if (reset_2pole == 0) cs.first();
    else croak("nope");
    reset_2pole = -1;
  }
  if (cs.null()) return;
  OSSV *ossv = (OSSV*) cs.retrieve();
  push_hkey_ossv((hkey*) (ossv? ((OSPV_hvdict*)focus())->hv.retrieve_key(cs):0),ossv);
}

void OSPV_hvdict_cs::next()
{ at(); cs.next(); }

/*--------------------------------------------- */
/*--------------------------------------------- Set os_set */

XS(XS_ObjStore__Set__new_os_set)
{
  dXSARGS;
  if (items != 3) croak("Usage: &$create('ObjStore::Set', $segment, $card)");
  SP -= items;

  dOSP ;
  char *clsv = SvPV(ST(0), na);
  os_segment *area = osp->sv_2segment(ST(1));
  int card = (int)SvIV(ST(2));
  PUTBACK;

  if (card <= 0) croak("Non-positive cardinality");

  OSSVPV *pv = new(area, OSPV_sethash::get_os_typespec()) OSPV_sethash(card);
  pv->_bless(clsv);
  osp->push_ospv(pv);
}

void OSPV_sethash::_boot(HV *hv)
{ install_rep(hv, file, "os_set", XS_ObjStore__Set__new_os_set); }

OSPV_sethash::OSPV_sethash(os_unsigned_int32 size)
  : set(size)
{
  //  warn("new OSPV_sethash(%d)", size);
}

OSPV_sethash::~OSPV_sethash()
{ CLEAR(); }

int OSPV_sethash::_count()
{ return set.cardinality(); }

char *OSPV_sethash::base_class()
{ return "ObjStore::Set"; }

void OSPV_sethash::add(SV *nval)
{
  dOSP ;
  ossv_bridge *mg = osp->sv_2bridge(nval, 1, os_segment::of(this));
  OSSVPV *ospv = mg->ospv();
  if (!ospv) croak("OSPV_sethash::add(SV*): cannot add non-object");
  ospv->REF_inc();

  set.insert(ospv);
}

int OSPV_sethash::contains(SV *nval)
{
  dOSP ;
  OSSVPV *ospv=0;
  ossv_bridge *mg = osp->sv_2bridge(nval, 0);
  if (mg) ospv = mg->ospv();
  if (!ospv) croak("OSPV_sethash::contains(SV *nval): cannot test non-object");
  return set.contains(ospv);
}

void OSPV_sethash::rm(SV *nval)
{
  dOSP ;
  OSSVPV *ospv=0;
  ossv_bridge *mg = osp->sv_2bridge(nval, 0);
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
  dOSP ;
  return osp->ospv_2sv( (OSSVPV*) mg->cs->first());
}

SV *OSPV_sethash::NEXT(ossv_bridge *vmg)
{
  sethash_bridge *mg = (sethash_bridge *) vmg;
  assert(mg);
  assert(mg->cs);
  dOSP ;
  return osp->ospv_2sv( (OSSVPV*) mg->cs->next());
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
{ return new(seg, OSPV_sethash_cs::get_os_typespec()) OSPV_sethash_cs(this); }

OSPV_sethash_cs::OSPV_sethash_cs(OSPV_sethash *_at)
  : OSPV_Cursor(_at), cs(_at->set)
{ seek_pole(0); }

void OSPV_sethash_cs::seek_pole(int end)
{ reset_2pole = end; }

void OSPV_sethash_cs::at()
{ croak("OSPV_sethash_cs::at() not implemented"); }

void OSPV_sethash_cs::next()
{
  if (reset_2pole != -1) {
    if (reset_2pole == 0) cs.first();
    else croak("not supported");
    reset_2pole = -1;
  }
  if (cs.null()) return;
  OSSVPV *pv = (OSSVPV*) cs.retrieve();
  dOSP ;
  osp->push_ospv(pv);
  cs.next();
}

/*--------------------------------------------- */
/*--------------------------------------------- NEW */
/*--------------------------------------------- */

hvent2::hvent2() : hk(0)
{}

hvent2::~hvent2()
{ set_undef(); }

void hvent2::set_undef()
{ if (hk) delete [] hk; hk=0; hv.set_undef(); }

int hvent2::valid() const
{ return hk != 0; }

void hvent2::set_key(char *nkey)
{
  assert(nkey);
  set_undef();
  int len = strlen(nkey)+1;
  hk = new(os_segment::of(this), os_typespec::get_char(), len) char[len];
  memcpy(hk, nkey, len);
}

SV *hvent2::key_2sv()
{
  assert(hk);
  return sv_2mortal(newSVpv(hk, 0));
}

hvent2 *hvent2::operator=(int zero)
{
  assert(zero==0);
  set_undef();
  return this;
}

hvent2 *hvent2::operator=(const hvent2 &nval)
{
  set_undef();
  if (nval.valid()) {
    set_key(nval.hk);
    hv.operator=((OSSV&) nval.hv);
  }
  return this;
}

int hvent2::rank(const char *v2)
{
  assert(hk != 0 && v2 != 0);
  return strcmp(hk, v2);
}

/*--------------------------------------------- */
/*--------------------------------------------- AV splash_array */

XS(XS_ObjStore__AV__new_splash_array)
{
  dXSARGS;
  if (items != 3) croak("Usage: &$create($class, $segment, $card)");
  SP -= items;

  dOSP ;
  char *clsv = SvPV(ST(0), na);
  os_segment *area = osp->sv_2segment(ST(1));
  int card = (int)SvIV(ST(2));
  PUTBACK;

  if (card <= 0) {
    croak("Non-positive cardinality");
  } else if (card > 100000) {
    card = 100000;
    warn("Cardinality > 100000; try a more suitable representation");
  }
  
  OSSVPV *pv = new(area, OSPV_avarray::get_os_typespec()) OSPV_avarray(card);
  pv->_bless(clsv);
  osp->push_ospv(pv);
}

OSPV_avarray::OSPV_avarray(int sz)
  : av(sz,8)
{}

OSPV_avarray::~OSPV_avarray()
{ CLEAR(); }

void OSPV_avarray::_boot(HV *hv)
{ install_rep(hv, file, "splash_array", XS_ObjStore__AV__new_splash_array); }

double OSPV_avarray::_percent_filled()
{
  I32 used=0;
  for (int xx=0; xx < av.size_allocated(); xx++) { used += av[xx].is_set(); }
  return used / (double) av.size_allocated();
}

int OSPV_avarray::_count()
{ return av.count(); }

char *OSPV_avarray::base_class()
{ return "ObjStore::AV"; }

int OSPV_avarray::get_perl_type()
{ return SVt_PVAV; }

SV *OSPV_avarray::FETCHi(int xx)
{
  if (xx < 0) return &sv_undef;
  DEBUG_array(warn("OSPV_avarray(0x%x)->FETCHi(%d)", this, xx));
  dOSP ;
  return osp->ossv_2sv(&av[xx]);
}

SV *OSPV_avarray::STOREi(int xx, SV *value)
{
  if (xx < 0) return &sv_undef;
  DEBUG_array(warn("OSPV_avarray(0x%x)->STOREi(%d)", this, xx));
  av[xx] = value;
  if (GIMME_V == G_VOID) return 0;
  dOSP ;
  return osp->ossv_2sv(&av[xx]);
}

SV *OSPV_avarray::Pop()
{	
  SV *ret = &sv_undef;
  int n= av.count()-1;
  if (n >= 0) {
    dOSP ;
    ret = osp->ossv_2sv(&av[n]);
    av.compact(n);
  }
  return ret;
}

SV *OSPV_avarray::Unshift()
{
  SV *ret = &sv_undef;
  if (av.count()) {
    dOSP ;
    ret = osp->ossv_2sv(&av[0]);
    av.compact(0);
  }
  return ret;
}

void OSPV_avarray::Push(SV *nval)
{ av[av.count()] = nval; }

void OSPV_avarray::CLEAR()
{ for (int xx=0; xx < av.count(); xx++) { av[xx].set_undef(); } }

OSPV_Cursor *OSPV_avarray::new_cursor(os_segment *seg)
{ return new(seg, OSPV_avarray_cs::get_os_typespec()) OSPV_avarray_cs(this); }

OSPV_avarray_cs::OSPV_avarray_cs(OSPV_avarray *_at)
  : OSPV_Cursor(_at)
{ seek_pole(0); }

void OSPV_avarray_cs::seek_pole(int end)
{
  OSPV_avarray *pv = (OSPV_avarray*)focus();
  if (!end) cs=0;
  else cs = pv->av.count()-1;
}

void OSPV_avarray_cs::at()
{
  OSPV_avarray *pv = (OSPV_avarray*)focus();
  int cnt = pv->av.count();
  if (cs >= 0 && cs < cnt) push_index_ossv(cs, &pv->av[cs]);
}

void OSPV_avarray_cs::next()
{
  OSPV_avarray *pv = (OSPV_avarray*)focus();
  int cnt = pv->av.count();
  at();
  if (cs < cnt) ++cs;
}

/*--------------------------------------------- */
/*--------------------------------------------- HV splash array #2 */

XS(XS_ObjStore__HV__new_splash_array2)
{
  dXSARGS;
  if (items != 3) croak("Usage: &$create('ObjStore::HV', $segment, $card)");
  SP -= items;

  dOSP ;
  char *clsv = SvPV(ST(0), na);
  os_segment *area = osp->sv_2segment(ST(1));
  int card = (int)SvIV(ST(2));
  PUTBACK;
  
  if (card <= 0) {
    croak("Non-positive cardinality");
  } else if (card > 1000) {
    card = 1000;
    warn("Cardinality > 1000; try a more suitable representation");
  }
  
  OSSVPV *pv = new(area, OSPV_hvarray2::get_os_typespec()) OSPV_hvarray2(card);
  pv->_bless(clsv);
  osp->push_ospv(pv);
}

void OSPV_hvarray2::_boot(HV *hv)
{ install_rep(hv, file, "splash_array", XS_ObjStore__HV__new_splash_array2); }

OSPV_hvarray2::OSPV_hvarray2(int sz)
  : hv(sz,8)
{}

OSPV_hvarray2::~OSPV_hvarray2()
{ CLEAR(); }

double OSPV_hvarray2::_percent_filled()
{
  I32 used=0;
  for (int xx=0; xx < hv.size_allocated(); xx++) { used += hv[xx].valid(); }
  return used / (double) hv.size_allocated();
}

int OSPV_hvarray2::_count()
{ return hv.count(); }

char *OSPV_hvarray2::base_class()
{ return "ObjStore::HV"; }

int OSPV_hvarray2::get_perl_type()
{ return SVt_PVHV; }

int OSPV_hvarray2::index_of(char *key)
{
//  warn("OSPV_hvarray2::index_of(%s)", key);
  int ok=0;
  for (int xx=0; xx < hv.count(); xx++) {
    if (hv[xx].valid() && hv[xx].rank(key) == 0) return xx;
  }
  return -1;
}

SV *OSPV_hvarray2::FETCHp(char *key)
{
  int xx = index_of(key);
  OSSV *ret = xx==-1? 0 : &hv[xx].hv;
  DEBUG_hash(warn("OSPV_hvarray2::FETCH[%d] %s => %s",
		  xx, key, ret?ret->as_pv():"undef"));
  dOSP ;
  return osp->ossv_2sv(ret);
}

SV *OSPV_hvarray2::STOREp(char *key, SV *value)
{
  int xx = index_of(key);
  if (xx == -1) {
    xx = hv.count();
    hv[hv.count()].set_key(key);
  }
  hv[xx].hv = value;
  DEBUG_hash(warn("OSPV_hvarray2::STORE[%x] %s => %s",
		  xx, key, hv[xx].hv.as_pv()));
  if (GIMME_V == G_VOID) return 0;
  dOSP ;
  return osp->ossv_2sv(&hv[xx].hv);
}

void OSPV_hvarray2::DELETE(char *key)
{
  int xx = index_of(key);
  if (xx != -1) hv[xx].set_undef();
}

void OSPV_hvarray2::CLEAR()
{
  int cursor = 0;
  while ((cursor = first(cursor)) != -1) {
    hv[cursor].set_undef();
    cursor++;
  }
}

int OSPV_hvarray2::EXISTS(char *key)
{ return index_of(key) != -1; }

int OSPV_hvarray2::first(int start)
{
  int xx;
  for (xx=start; xx < hv.count(); xx++) {
    if (hv[xx].valid()) return xx;
  }
  return -1;
}

struct hvarray2_bridge : ossv_bridge {
  int cursor;
  hvarray2_bridge(OSSVPV *);
};
hvarray2_bridge::hvarray2_bridge(OSSVPV *_pv) : ossv_bridge(_pv), cursor(0)
{}

ossv_bridge *OSPV_hvarray2::_new_bridge(OSSVPV *pv)
{ return new hvarray2_bridge(pv); }

SV *OSPV_hvarray2::FIRST(ossv_bridge *vmg)
{
  hvarray2_bridge *mg = (hvarray2_bridge *) vmg;
  SV *out;
  mg->cursor = first(0);
  if (mg->cursor != -1) {
    out = hv[mg->cursor].key_2sv();
  } else {
    out = &sv_undef;
  }
  return out;
}

SV *OSPV_hvarray2::NEXT(ossv_bridge *vmg)
{
  hvarray2_bridge *mg = (hvarray2_bridge *) vmg;
  SV *out;
  mg->cursor++;
  mg->cursor = first(mg->cursor);
  if (mg->cursor != -1) {
    out = hv[mg->cursor].key_2sv();
  } else {
    out = &sv_undef;
  }
  return out;
}

OSPV_Cursor *OSPV_hvarray2::new_cursor(os_segment *seg)
{ return new(seg, OSPV_hvarray2_cs::get_os_typespec()) OSPV_hvarray2_cs(this); }

OSPV_hvarray2_cs::OSPV_hvarray2_cs(OSPV_hvarray2 *_at)
  : OSPV_Cursor(_at)
{ seek_pole(0); }

void OSPV_hvarray2_cs::seek_pole(int end)
{
  OSPV_hvarray2 *pv = (OSPV_hvarray2*)focus();
  if (!end) cs = 0;
  else cs = pv->hv.count()-1;
}

void OSPV_hvarray2_cs::at()
{
  OSPV_hvarray2 *pv = (OSPV_hvarray2*)focus();
  int cnt = pv->hv.count();
  if (cs >= 0 && cs < cnt) push_sv_ossv(pv->hv[cs].key_2sv(), &pv->hv[cs].hv);
}

void OSPV_hvarray2_cs::next()
{
  OSPV_hvarray2 *pv = (OSPV_hvarray2*)focus();
  int cnt = pv->hv.count();
  at();
  if (cs < cnt) ++ cs;
  if (cs < cnt) { cs = pv->first(cs); if (cs==-1) cs = cnt; }
}


MODULE = ObjStore::GENERIC	PACKAGE = ObjStore::GENERIC

BOOT:
  SV *rep;
  char *tag;
#ifdef USE_THREADS
  os_collection::set_thread_locking(1);
#else
  os_collection::set_thread_locking(0);
#endif
  os_index_key(hkey, hkey::rank, hkey::hash);
  // AV
  HV *avrep = perl_get_hv("ObjStore::AV::REP", TRUE);
  OSPV_avarray::_boot(avrep);
  // HV
  HV *hvrep = perl_get_hv("ObjStore::HV::REP", TRUE);
  OSPV_hvarray2::_boot(hvrep);
  OSPV_hvdict::_boot(hvrep);

