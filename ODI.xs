// -*-C++-*- mode
#include "osperl.h"
#include "GENERIC.h"
#include "ODI.h"

/* CCov: fatal SERIOUS */
#define SERIOUS warn

/*--------------------------------------------- */
/*--------------------------------------------- HV os_dictionary */

OSPV_hvdict::OSPV_hvdict(os_unsigned_int32 card)
  : hv(card,
       os_dictionary::signal_dup_keys |
       os_collection::pick_from_empty_returns_null |
       os_dictionary::dont_maintain_cardinality)
{}

OSPV_hvdict::~OSPV_hvdict()
{
  os_cursor cs(hv);
  OSSV *at;
  for (at = (OSSV*) cs.first(); at; at = (OSSV*) cs.next()) {
    delete at;
  }
}

int OSPV_hvdict::_count()
{ return hv.update_cardinality(); }

char *OSPV_hvdict::os_class(STRLEN *len)
{ *len = 12; return "ObjStore::HV"; }

char *OSPV_hvdict::rep_class(STRLEN *len)
{ *len = 22; return "ObjStore::REP::ODI::HV"; }

int OSPV_hvdict::get_perl_type()
{ return SVt_PVHV; }

OSSV *OSPV_hvdict::hvx(char *key)
{
  OSSV *ret = hv.pick(key);
  DEBUG_hash(warn("OSPV_hvdict::FETCH %s => %s", key, ret? ret->stringify() : "<0x0>"));
  return ret;
}

OSSV *OSPV_hvdict::FETCH(SV *key)
{ return hvx(SvPV(key,na)); }

OSSV *OSPV_hvdict::traverse(char *keyish)
{ return hvx(keyish); }

void OSPV_hvdict::XSHARE(int on)
{
  os_cursor cs(hv);
  OSSV *at;
  for (at = (OSSV*) cs.first(); at; at = (OSSV*) cs.next()) {
    OSvXSHARED_set(at, on);
  }
}

OSSV *OSPV_hvdict::STORE(SV *sv, SV *nval)
{
  STRLEN keylen;
  char *key = SvPV(sv,keylen);
  if (keylen == 0)
    croak("ObjStore: os_dictionary cannot store a zero length hash key");
  OSSV *ossv = (OSSV*) hv.pick(key);
  dOSP;
  if (ossv) {
    *ossv = nval;
  } else {
    ossv = osp->plant_sv(os_segment::of(this), nval);
    hv.insert(key, ossv);
  }
  DEBUG_hash(warn("OSPV_hvdict::INSERT(%s=%s)", key, ossv->stringify()));
  //  dTHR;
  //  if (GIMME_V == G_VOID) return 0;
  return ossv;
}

void OSPV_hvdict::DELETE(char *key)
{
  OSSV *val = hv.pick(key);
  if (!val) return;
  hv.remove_value(key);
  DEBUG_hash(warn("OSPV_hvdict::DELETE(%s) deleting hash value 0x%x", key, val));
  val->set_undef();
  delete val;
}

void OSPV_hvdict::CLEAR()
{
  os_cursor cs(hv);
  OSSV *at;
  for (at = (OSSV*) cs.first(); at; at = (OSSV*) cs.next()) {
    assert(at);
    at->set_undef();
    delete at;
  }
  hv.clear();
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

ossv_bridge *OSPV_hvdict::new_bridge()
{ return new hvdict_bridge(this); }

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
  return k1->to_sv();
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
  return k1->to_sv();
}

OSSVPV *OSPV_hvdict::new_cursor(os_segment *seg)
{ return new(seg, OSPV_hvdict_cs::get_os_typespec()) OSPV_hvdict_cs(this); }

OSPV_hvdict_cs::OSPV_hvdict_cs(OSPV_hvdict *_at)
  : OSPV_Cursor(_at), cs(_at->hv)
{ seek_pole(0); }

void OSPV_hvdict_cs::seek_pole(int end)
{
  reset_2pole = end;
  if (end) { 
    SERIOUS("seek_pole('end') is experimental");
  }
}

void OSPV_hvdict_cs::at()
{
  if (reset_2pole != -1) {
    if (reset_2pole == 0) cs.first();
    else croak("nope");
    reset_2pole = -1;
  }
  if (cs.null()) return;

  OSSV *ossv = (OSSV*) cs.retrieve();
  if (ossv) {
    dOSP;
    SV *sv[2] = {
      ((hkey*) ((OSPV_hvdict*)focus())->hv.retrieve_key(cs))->to_sv(),
      osp->ossv_2sv(ossv)
    };
    dSP;
    EXTEND(SP,2);
    PUSHs(sv[0]);
    PUSHs(sv[1]);
    PUTBACK;
  }
}

void OSPV_hvdict_cs::next()
{ at(); cs.next(); }



MODULE = ObjStore::REP::ODI		PACKAGE = ObjStore::REP::ODI

BOOT:
  HV *hvrep = perl_get_hv("ObjStore::HV::REP", TRUE);
  hv_store(hvrep, "ObjStore::REP::ODI::HV", 22, newSViv(1), 0);
  os_index_key(hkey, hkey::rank, hkey::hash);
#ifdef USE_THREADS
  os_collection::set_thread_locking(1);
#else
  os_collection::set_thread_locking(0);
#endif
  HV *szof = perl_get_hv("ObjStore::sizeof", TRUE);
  hv_store(szof, "OSPV_hvdict", 11, newSViv(sizeof(OSPV_hvdict)), 0);

MODULE = ObjStore::REP::ODI		PACKAGE = ObjStore::REP::ODI::HV

static void
OSPV_hvdict::new(seg, sz)
	SV *seg;
	int sz;
	PPCODE:
	dOSP;
	os_segment *area = osp->sv_2segment(ST(1));
	PUTBACK;
	if (sz <= 0) croak("Non-positive cardinality");
	OSSVPV *pv = new(area, OSPV_hvdict::get_os_typespec()) OSPV_hvdict(sz);
	pv->bless(ST(0));
	return;

