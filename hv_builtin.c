// Hash -*-c++-*-
#include "osperl.hh"

/*--------------------------------------------- registration */

struct BEGIN_hvarray {
  BEGIN_hvarray();
  static void *mk(os_segment *seg, char *name, os_unsigned_int32 card);
};
BEGIN_hvarray::BEGIN_hvarray()
{ osperl::register_spec("ObjStore::HV::Array", mk); }

void *BEGIN_hvarray::mk(os_segment *seg, char *name, os_unsigned_int32 card)
{
  if (card > 10000) {
    card = 10000;
    warn("hvarray: cardinality cannot be greater than 10000");
  }
  return new(seg, OSPV_hvarray::get_os_typespec()) OSPV_hvarray(card);
}

static BEGIN_hvarray run_hvarray;

/*--------------------------------------------- hvarray */

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

OSSV *OSPV_hvarray::FETCHp(char *key)
{
  int xx = index_of(key);
  if (xx == -1) {
    return 0;
  } else {
    return &hv[xx].hv;
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
  return osperl::ossv_2sv(&hv[xx].hv);  // may become invalid if array grows... XXX
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

struct hvarray_magic : ossv_magic {
  int cursor;
  hvarray_magic(OSSV *, OSSVPV *);
};
hvarray_magic::hvarray_magic(OSSV *_sv, OSSVPV *_pv) : ossv_magic(_sv,_pv), cursor(0)
{}

ossv_magic *OSPV_hvarray::NEW_MAGIC(OSSV *sv, OSSVPV *pv)
{ return new hvarray_magic(sv,pv); }

SV *OSPV_hvarray::FIRST(ossv_magic *vmg)
{
  hvarray_magic *mg = (hvarray_magic *) vmg;
  SV *out;
  mg->cursor = first(0);
  if (mg->cursor != -1) {
    out = osperl::hkey_2sv(&hv[mg->cursor].hk);
  } else {
    out = &sv_undef;
  }
  return out;
}

SV *OSPV_hvarray::NEXT(ossv_magic *vmg)
{
  hvarray_magic *mg = (hvarray_magic *) vmg;
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

/*--------------------------------------------- registration */

struct BEGIN_hvdict {
  BEGIN_hvdict();
  static void *mk(os_segment *seg, char *name, os_unsigned_int32 card);
};
BEGIN_hvdict::BEGIN_hvdict()
{ osperl::register_spec("ObjStore::HV::Dict", mk); }

void *BEGIN_hvdict::mk(os_segment *seg, char *name, os_unsigned_int32 card)
{ return new(seg, OSPV_hvdict::get_os_typespec()) OSPV_hvdict(card); }

static BEGIN_hvdict run_hvdict;

/*--------------------------------------------- hvdict */

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

OSSV *OSPV_hvdict::FETCHp(char *key)
{
  OSSV *ret = hv.pick(key);
#ifdef DEBUG_HVDICT
  warn("OSPV_hvdict::FETCH %s => %s", key, ret? ret->as_pv() : "<0x0>");
#endif
  return ret;
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
    ossv_magic *mg = osperl::sv_2magic(nval);
    if (mg) ossv = mg->force_ossv();
  }
  if (!ossv) {
    ossv = new(WHERE, OSSV::get_os_typespec()) OSSV(nval);
#ifdef DEBUG_NEW_OSSV
    warn("OSPV_hvdict::STOREp(%s, SV *nval, SV **out): new OSSV = 0x%x", key, ossv);
#endif
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

struct hvdict_magic : ossv_magic {
  os_cursor *cs;
  hvdict_magic(OSSV *, OSSVPV *);
  virtual ~hvdict_magic();
};
hvdict_magic::hvdict_magic(OSSV *_sv, OSSVPV *_pv) : ossv_magic(_sv,_pv), cs(0)
{}
hvdict_magic::~hvdict_magic()
{ if (cs) delete cs; }

ossv_magic *OSPV_hvdict::NEW_MAGIC(OSSV *_sv, OSSVPV *_pv)
{ return new hvdict_magic(_sv,_pv); }

SV *OSPV_hvdict::FIRST(ossv_magic *vmg)
{
  hvdict_magic *mg = (hvdict_magic *) vmg;
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

SV *OSPV_hvdict::NEXT(ossv_magic *vmg)
{
  hvdict_magic *mg = (hvdict_magic *) vmg;
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
