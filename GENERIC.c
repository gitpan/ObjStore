// -*-C++-*- mode
// THIS ENTIRE FILE IS DEPRECIATED (but included for backward compatibility)
/* CCov: off */

#include "osperl.h"
#include "GENERIC.h"

static void push_ospv(OSSVPV *pv)
{
  dOSP ;
  if (!pv) return;
  SV *sv = osp->ospv_2sv(pv);
  dSP;
  PUSHs(sv);
  PUTBACK;
}

static void push_hkey_ossv(hkey *hk, OSSV *hv)
{
  if (!hk && !hv) return;
  assert(hk && hv);
  dOSP ;
  SV *sv[2] = {hk->to_sv(), osp->ossv_2sv(hv)};
  dSP;
  EXTEND(SP, 2);
  PUSHs(sv[0]);
  PUSHs(sv[1]);
  PUTBACK;
}

/*--------------------------------------------- */
/*--------------------------------------------- HV splash array */

void hent::set_undef()
{ hk.set_undef(); hv.set_undef(); }

hent *hent::operator=(const hent &nval)
{
  hk.operator=(nval.hk); hv.operator=( (OSSV&) nval.hv);
  return this;
}

void hent::FORCEUNDEF()
{}

OSPV_hvarray::OSPV_hvarray(int sz)
  : hv(sz,8)
{}

OSPV_hvarray::~OSPV_hvarray()
{}

double OSPV_hvarray::_percent_filled()
{
  I32 used=0;
  for (int xx=0; xx < hv.size_allocated(); xx++) { used += hv[xx].hk.valid(); }
  return used / (double) hv.size_allocated();
}

int OSPV_hvarray::_count()
{ return hv.count(); }

char *OSPV_hvarray::os_class(STRLEN *len)
{ *len = 12; return "ObjStore::HV"; }

int OSPV_hvarray::get_perl_type()
{ return SVt_PVHV; }

int OSPV_hvarray::index_of(char *key)
{
//  warn("OSPV_hvarray::index_of(%s)", key);
  hkey look(key);
  int ok=0;
  for (int xx=0; xx < hv.count(); xx++) {
    if (hkey::rank(&hv[xx].hk, &look) == 0) return xx;
  }
  return -1;
}

OSSV *OSPV_hvarray::hvx(char *key)
{
  int xx = index_of(key);
  if (xx == -1) {
    return 0;
  } else {
    return &hv[xx].hv;
  }
}

OSSV *OSPV_hvarray::FETCH(SV *sv)
{ return traverse(SvPV(sv,na)); }

OSSV *OSPV_hvarray::traverse(char *key)
{ return hvx(key); }

void OSPV_hvarray::XSHARE(int on)
{
  for (int xx=0; xx < hv.count(); xx++) {
    OSvXSHARED_set(&hv[xx].hv, on);
  }
}

OSSV *OSPV_hvarray::STORE(SV *sv, SV *value)
{
  char *key = SvPV(sv,na);
  int xx = index_of(key);
  if (xx == -1) {
    xx = hv.count();
    hv[hv.count()].hk.s(key, strlen(key)+1);
  }
  hv[xx].hv = value;
  dTHR;
  if (GIMME_V == G_VOID) return 0;
  return &hv[xx].hv;
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

struct hvarray_bridge : ospv_bridge {
  int cursor;
  hvarray_bridge(OSSVPV *);
};
hvarray_bridge::hvarray_bridge(OSSVPV *_pv) : ospv_bridge(_pv), cursor(0)
{}

ospv_bridge *OSPV_hvarray::new_bridge()
{ return new hvarray_bridge(this); }

SV *OSPV_hvarray::FIRST(ospv_bridge *vmg)
{
  hvarray_bridge *mg = (hvarray_bridge *) vmg;
  SV *out;
  mg->cursor = first(0);
  if (mg->cursor != -1) {
    out = hv[mg->cursor].hk.to_sv();
  } else {
    out = &sv_undef;
  }
  return out;
}

SV *OSPV_hvarray::NEXT(ospv_bridge *vmg)
{
  hvarray_bridge *mg = (hvarray_bridge *) vmg;
  SV *out;
  mg->cursor++;
  mg->cursor = first(mg->cursor);
  if (mg->cursor != -1) {
    out = hv[mg->cursor].hk.to_sv();
  } else {
    out = &sv_undef;
  }
  return out;
}

OSSVPV *OSPV_hvarray::new_cursor(os_segment *seg)
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

OSPV_setarray::OSPV_setarray(int size)
  : cv(size,8)
{
  //  warn("new OSPV_setarray(%d)", size);
}

OSPV_setarray::~OSPV_setarray()
{}

double OSPV_setarray::_percent_filled()
{
  I32 used=0;
  for (int xx=0; xx < cv.size_allocated(); xx++) { used += cv[xx].is_set(); }
  return used / (double) cv.size_allocated();
}

int OSPV_setarray::_count()
{ return cv.count(); }

char *OSPV_setarray::os_class(STRLEN *len)
{ *len = 13; return "ObjStore::Set"; }

int OSPV_setarray::first(int start)
{
  int xx;
  for (xx=start; xx < cv.count(); xx++) {
    if (cv[xx].natural() != OSVt_UNDEF) return xx;
  }
  return -1;
}

void OSPV_setarray::set_add(SV *nval)
{
  int spot=-1;
  // stupid, but definitely correct
  for (int xx=0; xx < cv.count(); xx++) {
    if (cv[xx].natural() != OSVt_UNDEF) continue;
    spot = xx;
    break;
  }
  if (spot == -1) spot = cv.count();
  cv[spot] = nval;
  if (cv[spot].natural() != OSVt_RV)
    croak("OSPV_setarray::add(nval): sets can only contain objects");

  //  warn("added %s", cv[spot].stringify());
  /*
  for (int zz=0; zz < cv.count(); zz++) {
    warn("cv[%d]: %d\n", zz, cv[zz].natural());
  }
  */
}

int OSPV_setarray::set_contains(SV *val)
{
  dOSP ;
  OSSVPV *pv = 0;
  ospv_bridge *mg = osp->sv_2bridge(val, 0);
  if (mg) pv = mg->ospv();
  if (!pv) croak("OSPV_setarray::contains(SV *val): must be persistent object");

  for (int xx=0; xx < cv.count(); xx++) {
    if (cv[xx].vptr == pv) return 1;
  }
  return 0;
}

void OSPV_setarray::set_rm(SV *nval)
{
  dOSP ;
  OSSVPV *pv = 0;
  ospv_bridge *mg = osp->sv_2bridge(nval, 0);
  if (mg) pv = mg->ospv();
  if (!pv) croak("OSPV_setarray::rm(SV *val): must be persistent object");

  // stupid, but definitely correct
  for (int xx=0; xx < cv.count(); xx++) {
    if (cv[xx].vptr == pv) {
      cv[xx].set_undef();
      return;
    }
  }
}

struct setarray_bridge : ospv_bridge {
  int cursor;
  setarray_bridge(OSSVPV *);
};
setarray_bridge::setarray_bridge(OSSVPV *_pv) : ospv_bridge(_pv), cursor(0)
{}

ospv_bridge *OSPV_setarray::new_bridge()
{ return new setarray_bridge(this); }

SV *OSPV_setarray::FIRST(ospv_bridge *vmg)
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

SV *OSPV_setarray::NEXT(ospv_bridge *vmg)
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

OSSVPV *OSPV_setarray::new_cursor(os_segment *seg)
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
    push_ospv((OSSVPV*) pv->cv[cs].vptr);
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
/*--------------------------------------------- Set os_set */

OSPV_sethash::OSPV_sethash(os_unsigned_int32 size)
  : set(size)
{
  //  warn("new OSPV_sethash(%d)", size);
}

OSPV_sethash::~OSPV_sethash()
{ CLEAR(); }

int OSPV_sethash::_count()
{ return set.cardinality(); }

char *OSPV_sethash::os_class(STRLEN *len)
{ *len = 13; return "ObjStore::Set"; }

void OSPV_sethash::set_add(SV *nval)
{
  dOSP ;
  ospv_bridge *mg = osp->sv_2bridge(nval, 1, os_segment::of(this));
  OSSVPV *ospv = mg->ospv();
  if (!ospv) croak("OSPV_sethash::add(SV*): cannot add non-object");
  ospv->REF_inc();

  set.insert(ospv);
}

int OSPV_sethash::set_contains(SV *nval)
{
  dOSP ;
  OSSVPV *ospv=0;
  ospv_bridge *mg = osp->sv_2bridge(nval, 0);
  if (mg) ospv = mg->ospv();
  if (!ospv) croak("OSPV_sethash::contains(SV *nval): cannot test non-object");
  return set.contains(ospv);
}

void OSPV_sethash::set_rm(SV *nval)
{
  dOSP ;
  OSSVPV *ospv=0;
  ospv_bridge *mg = osp->sv_2bridge(nval, 0);
  if (mg) ospv = mg->ospv();
  if (!ospv) croak("OSPV_sethash::rm(SV *nval): cannot remove non-object");
  if (set.remove(ospv)) ospv->REF_dec();
}

struct sethash_bridge : ospv_bridge {
  os_cursor *cs;
  sethash_bridge(OSSVPV *);
};
sethash_bridge::sethash_bridge(OSSVPV *_pv) : ospv_bridge(_pv), cs(0)
{}

ospv_bridge *OSPV_sethash::new_bridge()
{ return new sethash_bridge(this); }

SV *OSPV_sethash::FIRST(ospv_bridge *vmg)
{
  sethash_bridge *mg = (sethash_bridge *) vmg;
  assert(mg);
  if (!mg->cs) mg->cs = new os_cursor(set);
  dOSP ;
  return osp->ospv_2sv( (OSSVPV*) mg->cs->first());
}

SV *OSPV_sethash::NEXT(ospv_bridge *vmg)
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

OSSVPV *OSPV_sethash::new_cursor(os_segment *seg)
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
  push_ospv(pv);
  cs.next();
}
