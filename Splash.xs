// -*-C++-*- mode
#include "osperl.h"
#include "Splash.h"

/* CCov: fatal SERIOUS */
#define SERIOUS warn

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

// move pushes to ...?
static void push_index_ossv(int xx, OSSV *hv)
{
  assert(hv);
  dOSP ;
  SV *sv[2] = {sv_2mortal(newSViv(xx)), osp->ossv_2sv(hv)};
  dSP;
  EXTEND(SP, 2);
  PUSHs(sv[0]);
  PUSHs(sv[1]);
  PUTBACK;
}

hvent2::hvent2() : hk(0)
{}

hvent2::~hvent2()
{
  OSvXSHARED_set(&hv, 0);
  set_undef();
}

void hvent2::FORCEUNDEF()
{ hk=0; hv.FORCEUNDEF(); }

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

/* Added to support stupid C++ templates, then I decided just to rewrite
   all the collection types in C.
hvent2 *hvent2::operator=(int zero)
{
  assert(zero==0);
  set_undef();
  return this;
}
*/

int hvent2::rank(const char *v2)
{
  assert(hk != 0 && v2 != 0);
  return strcmp(hk, v2);
}

/*--------------------------------------------- */
/*--------------------------------------------- AV splash_array */

OSPV_avarray::OSPV_avarray(int sz)
  : av(sz,8)
{}

OSPV_avarray::~OSPV_avarray()
{}

double OSPV_avarray::_percent_filled()
{ croak("OSPV_avarray::_percent_filled: not implemented"); return -1; }

int OSPV_avarray::_count()
{ return av.count(); }

char *OSPV_avarray::os_class(STRLEN *len)
{ *len = 12; return "ObjStore::AV"; }

char *OSPV_avarray::rep_class(STRLEN *len)
{ *len = 25; return "ObjStore::REP::Splash::AV"; }

int OSPV_avarray::get_perl_type()
{ return SVt_PVAV; }

OSSV *OSPV_avarray::FETCH(SV *key)
{ return avx(SvIV(key)); }

OSSV *OSPV_avarray::avx(int xx)
{
  if (xx < 0 || xx >= av.count()) return 0;
  DEBUG_array(warn("OSPV_avarray(0x%x)->FETCH(%d)", this, xx));
  return &av[xx];
}

OSSV *OSPV_avarray::traverse(char *keyish)
{
  if (_is_blessed()) {
    // This will be optimized once overload '%' works XXX
    STRLEN bslen;
    char *bs = blessed_to(&bslen);
    assert(bs);
    SV *meth = (SV*) gv_fetchmethod(gv_stashpv("UNIVERSAL",0), "isa"); //XXX wrong
    assert(meth);
    dSP;
    PUSHMARK(SP);
    XPUSHs(sv_2mortal(newSVpv(bs, bslen)));
    XPUSHs(sv_2mortal(newSVpv("ObjStore::AVHV", 0)));
    PUTBACK;
    int items = perl_call_sv(meth, G_SCALAR);
    assert(items == 1);
    SPAGAIN;
    int avhv = SvTRUEx(POPs);
    PUTBACK;
    if (avhv) {
      OSPV_Generic *layout = (OSPV_Generic *) avx(0)->get_ospv();
      OSSV *ki = layout->hvx(keyish);
      if (!ki || ki->natural() != OSVt_IV16)
	croak("%p->traverse('%s'): key indexed to bizarre array slot", 
	      this, keyish);
      return avx(OSvIV16(ki));
    }
  }
  return avx(atol(keyish));
}

void OSPV_avarray::XSHARE(int on)
{
  for (int xx=0; xx < av.count(); xx++) {
    OSvXSHARED_set(&av[xx], on);
  }
}

OSSV *OSPV_avarray::STORE(SV *sv, SV *value)
{
  int xx = SvIV(sv);
  if (xx < 0) return 0;
  DEBUG_array(warn("OSPV_avarray(0x%x)->STORE(%d)", this, xx));
  av[xx] = value;
  dTHR;
  if (GIMME_V == G_VOID) return 0;
  return &av[xx];
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

/*
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
*/

void OSPV_avarray::Push(SV *nval)
{ av[av.count()] = nval; }

void OSPV_avarray::CLEAR()
{
  for (int xx=0; xx < av.count(); xx++) { av[xx].set_undef(); }
  av.reset();
  assert(av.count() == 0);
}

OSSVPV *OSPV_avarray::new_cursor(os_segment *seg)
{ return new(seg, OSPV_avarray_cs::get_os_typespec()) OSPV_avarray_cs(this); }

OSPV_avarray_cs::OSPV_avarray_cs(OSPV_avarray *_at)
  : OSPV_Cursor(_at)
{ seek_pole(0); }

void OSPV_avarray_cs::seek_pole(int end)
{
  OSPV_avarray *pv = (OSPV_avarray*)focus();
  if (!end) cs=0;
  else {
    cs = pv->av.count()-1;
    SERIOUS("seek_pole('end') is experimental");
  }
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

OSPV_hvarray2::OSPV_hvarray2(int sz)
  : hv(sz,8)
{}

OSPV_hvarray2::~OSPV_hvarray2()
{}

double OSPV_hvarray2::_percent_filled()
{ croak("OSPV_hvarray2::_percent_filled: not implemented"); return -1; }

int OSPV_hvarray2::_count()
{ return hv.count(); }

char *OSPV_hvarray2::os_class(STRLEN *len)
{ *len = 12; return "ObjStore::HV"; }

char *OSPV_hvarray2::rep_class(STRLEN *len)
{ *len = 25; return "ObjStore::REP::Splash::HV"; }

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

OSSV *OSPV_hvarray2::FETCH(SV *key)
{ return hvx(SvPV(key,na)); }

OSSV *OSPV_hvarray2::hvx(char *key)
{
  int xx = index_of(key);
  OSSV *ret = xx==-1? 0 : &hv[xx].hv;
  DEBUG_hash(warn("OSPV_hvarray2::FETCH[%d] %s => %s",
		  xx, key, ret?ret->stringify():"undef"));
  return ret;
}

OSSV *OSPV_hvarray2::traverse(char *keyish)
{ return hvx(keyish); }

void OSPV_hvarray2::XSHARE(int on)
{
  for (int xx=0; xx < hv.count(); xx++) {
    OSvXSHARED_set(&hv[xx].hv, on);
  }
}

OSSV *OSPV_hvarray2::STORE(SV *sv, SV *value)
{
  char *key = SvPV(sv,na);
  int xx = -1;
  int open = -1;
  for (int za=0; za < hv.count(); za++) {
    if (!hv[za].valid()) {
      open = za;
    } else {
      if (hv[za].rank(key) == 0) { xx = za; break; }
    }
  }
  if (xx == -1) xx = open;
  if (xx != -1) {
    hv[xx].set_key(key);
  }
  if (xx == -1) {
    xx = hv.count();
    hv[hv.count()].set_key(key);
  }
  hv[xx].hv = value;
  DEBUG_hash(warn("OSPV_hvarray2::STORE[%x] %s => %s",
		  xx, key, hv[xx].hv.stringify()));
  //  dTHR;
  //  if (GIMME_V == G_VOID) return 0;
  return &hv[xx].hv;
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
  hv.reset();
  assert(hv.count()==0);
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

ossv_bridge *OSPV_hvarray2::new_bridge()
{ return new hvarray2_bridge(this); }

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

OSSVPV *OSPV_hvarray2::new_cursor(os_segment *seg)
{ return new(seg, OSPV_hvarray2_cs::get_os_typespec()) OSPV_hvarray2_cs(this); }

OSPV_hvarray2_cs::OSPV_hvarray2_cs(OSPV_hvarray2 *_at)
  : OSPV_Cursor(_at)
{ seek_pole(0); }

void OSPV_hvarray2_cs::seek_pole(int end)
{
  OSPV_hvarray2 *pv = (OSPV_hvarray2*)focus();
  if (!end) cs = 0;
  else {
    cs = pv->hv.count()-1;
    SERIOUS("seek_pole('end') is experimental");
  }
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


MODULE = ObjStore::REP::Splash	PACKAGE = ObjStore::REP::Splash

BOOT:
  HV *avrep = perl_get_hv("ObjStore::AV::REP", TRUE);
  hv_store(avrep, "ObjStore::REP::Splash::AV", 25, newSViv(1), 0);
  HV *hvrep = perl_get_hv("ObjStore::HV::REP", TRUE);
  hv_store(hvrep, "ObjStore::REP::Splash::HV", 25, newSViv(1), 0);
  HV *szof = perl_get_hv("ObjStore::sizeof", TRUE);
  hv_store(szof, "OSPV_avarray", 12, newSViv(sizeof(OSPV_avarray)), 0);
  hv_store(szof, "OSPV_hvarray2", 13, newSViv(sizeof(OSPV_hvarray2)), 0);
  hv_store(szof, "hvent2", 6, newSViv(sizeof(hvent2)), 0);

MODULE = ObjStore::REP::Splash	PACKAGE = ObjStore::REP::Splash::AV

static void
OSPV_avarray::new(seg, sz)
	SV *seg;
	int sz;
	PPCODE:
	dOSP;
	SV *CSV = ST(0);
	os_segment *area = osp->sv_2segment(ST(1));
	PUTBACK;
	if (sz <= 0) {
	  croak("Non-positive cardinality");
	} else if (sz > 100000) {
	  sz = 100000;
	  SERIOUS("Cardinality > 100000; try a more suitable representation");
	}
	OSSVPV *pv = new(area, OSPV_avarray::get_os_typespec()) OSPV_avarray(sz);
	pv->bless(CSV);
	return;

MODULE = ObjStore::REP::Splash	PACKAGE = ObjStore::REP::Splash::HV

static void
OSPV_hvarray2::new(seg, sz)
	SV *seg;
	int sz;
	PPCODE:
	dOSP;
	SV *CSV = ST(0);
	os_segment *area = osp->sv_2segment(ST(1));
	PUTBACK;
	if (sz <= 0) {
	  croak("Non-positive cardinality");
	} else if (sz > 1000) {
	  sz = 1000;
	  SERIOUS("Cardinality > 1000; try a more suitable representation");
	}
	OSSVPV *pv = new(area,OSPV_hvarray2::get_os_typespec()) OSPV_hvarray2(sz);
	pv->bless(CSV);
	return;
