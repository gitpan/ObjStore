// -*-C++-*- mode
#include "osperl.h"
#include "FatTree.h"
#include "XSthr.h"

/* CCov: fatal SERIOUS */
#define SERIOUS warn

static const char *file = __FILE__;

struct FatTree_thr {
  XPVTC tc;
};
static FatTree_thr *construct_thr()
{
  FatTree_thr *ti = new FatTree_thr;
  init_tc(&ti->tc);
  return ti;
}
static void destory_thr(FatTree_thr *ti)
{
  TcTV(&ti->tc) = 0;
  free_tc(&ti->tc);
}
dTHRINIT(FatTree, construct_thr, destroy_thr);

#define dGCURSOR(dex)				\
  FatTree_thr *gl;				\
  THRINFO(FatTree, gl);				\
  tc_refocus(&gl->tc, dex)

//--------------------------- ---------------------------
OSPV_fattree_av::OSPV_fattree_av()
{ init_tv(&ary); }

OSPV_fattree_av::~OSPV_fattree_av()
{ avfree_tv(&ary); }

int OSPV_fattree_av::_count()
{ return TvFILL(&ary); }

char *OSPV_fattree_av::os_class(STRLEN *len)
{ *len = 12; return "ObjStore::AV"; }

char *OSPV_fattree_av::rep_class(STRLEN *len)
{ *len = 26; return "ObjStore::REP::FatTree::AV"; }

int OSPV_fattree_av::get_perl_type()
{ return SVt_PVAV; }

OSSV *OSPV_fattree_av::FETCH(SV *key)
{ return avx(SvIV(key)); }

OSSV *OSPV_fattree_av::avx(int xx)
{
  if (xx < 0 || xx >= TvFILL(&ary)) return 0;
  dGCURSOR(&ary);
  tc_moveto(&gl->tc, xx);
  OSSV *ret=0;
  avtc_fetch(&gl->tc, &ret);
  return ret;
}

OSSV *OSPV_fattree_av::traverse(char *keyish)
{
  // probably never support AVHV? XXX
  return avx(atol(keyish));
}

void OSPV_fattree_av::XSHARE(int on)
{
  OSSV *ret;
  dGCURSOR(&ary);
  tc_moveto(&gl->tc, 0);
  while (1) {
    if (!avtc_fetch(&gl->tc, &ret)) break;
    OSvXSHARED_set(ret, on);
    tc_step(&gl->tc, 1);
  }
}

OSSV *OSPV_fattree_av::STORE(SV *sv, SV *value)
{
  int xx = SvIV(sv);
  if (xx < 0) return 0;
  dGCURSOR(&ary);
  tc_moveto(&gl->tc, xx);
  while (xx >= TvFILL(&ary)) {
    avtc_insert(&gl->tc, &sv_undef);
    tc_moveto(&gl->tc, xx);
  }
  avtc_store(&gl->tc, value);
  return 0;
}

SV *OSPV_fattree_av::Pop()
{	
  if (!TvFILL(&ary)) return 0;
  OSSV *ret0;
  dGCURSOR(&ary);
  tc_moveto(&gl->tc, TvFILL(&ary)-1);
  if (!avtc_fetch(&gl->tc, &ret0)) return 0;
  dOSP;
  SV *ret = osp->ossv_2sv(ret0);
  avtc_delete(&gl->tc);
  return ret;
}

void OSPV_fattree_av::Push(SV *nval)
{
  dGCURSOR(&ary);
  tc_moveto(&gl->tc, TvFILL(&ary)+1);
  avtc_insert(&gl->tc, nval);
}

void OSPV_fattree_av::CLEAR()
{
  OSSV *ret;
  dGCURSOR(&ary);
  tc_moveto(&gl->tc, 0);
  while (TvFILL(&ary)) {
    avtc_delete(&gl->tc);
  }
}

//--------------------------- ---------------------------

OSPV_fatindex2::OSPV_fatindex2()
{ init_tv(&tv); conf_slot=0; }

OSPV_fatindex2::~OSPV_fatindex2()
{
  CLEAR(); 
  dex2free_tv(&tv);
  if (conf_slot) conf_slot->REF_dec();
}

char *OSPV_fatindex2::os_class(STRLEN *len)
{ *len = 15; return "ObjStore::Index"; }

char *OSPV_fatindex2::rep_class(STRLEN *len)
{ *len = 29; return "ObjStore::REP::FatTree::Index"; }

int OSPV_fatindex2::get_perl_type()
{ return SVt_PVAV; }

void OSPV_fatindex2::CLEAR()
{
  if (conf_slot) {
    OSPV_Generic *conf = (OSPV_Generic *) conf_slot;
    OSPV_Generic *paths = (OSPV_Generic*) conf->avx(2)->get_ospv();
    dGCURSOR(&tv);
    tc_moveto(&gl->tc, 0);
    OSSVPV *pv;
    while (dex2tc_fetch(&gl->tc, &pv)) {
      osp_pathexam exam(paths, pv, 'u');
      pv->REF_dec();
      tc_step(&gl->tc, 1);
    }
  }
  dex2tv_clear(&tv);
}

void OSPV_fatindex2::add(OSSVPV *obj)
{
  if (!conf_slot) croak("Index(%p) is not configured", this);
  OSPV_Generic *conf = (OSPV_Generic *) conf_slot;
  dGCURSOR(&tv);
  OSPV_Generic *paths = (OSPV_Generic*) (conf)->avx(2)->get_ospv();
  osp_pathexam exam(paths, obj, 's');
  int unique = conf->avx(1)->istrue();
  int match = dex2tc_seek(&gl->tc, unique, exam.keycnt, exam.pcache, exam.keys);
  if (match && unique) {
    OSSVPV *here;
    dex2tc_fetch(&gl->tc, &here);
    if (here == obj) return;
    exam.abort();
    croak("%p->add(): attempt to insert duplicate record into a unique index",this);
  }
  obj->REF_inc();
  dex2tc_insert(&gl->tc, obj);
}

void OSPV_fatindex2::remove(OSSVPV *target)
{
  assert(conf_slot);
  dGCURSOR(&tv);
  OSPV_Generic *conf = (OSPV_Generic *) conf_slot;
  OSPV_Generic *paths = (OSPV_Generic*) conf->avx(2)->get_ospv();
  osp_pathexam exam(paths, target, 'u');
  int unique = conf->avx(1)->istrue();
  dex2tc_seek(&gl->tc, unique, exam.keycnt, exam.pcache, exam.keys);
  OSSVPV *obj;
  while (dex2tc_fetch(&gl->tc, &obj)) {
    if (obj == target) {
      dex2tc_delete(&gl->tc);
      target->REF_dec();
      return;
    }
    // Might step through a large number of records; no choice.
    tc_step(&gl->tc, 1);
  }
  croak("%p->remove(%p): record not found", this, target);
}

OSSVPV *OSPV_fatindex2::FETCHx(SV *key)
{
  if (!conf_slot) return 0;
  unsigned long xx = SvIV(key);
  dGCURSOR(&tv);
  tc_moveto(&gl->tc, xx);
  OSSVPV *pv=0;
  dex2tc_fetch(&gl->tc, &pv);
  return pv;
}

double OSPV_fatindex2::_percent_filled()
{ 
  SERIOUS("_percent_filled() is experimental");
  return TvFILL(&tv) / (double) (TvMAX(&tv) * dex2TnWIDTH);
}
int OSPV_fatindex2::_count()
{ return TvFILL(&tv); }

OSSVPV *OSPV_fatindex2::new_cursor(os_segment *seg)
{ return new(seg, OSPV_fatindex2_cs::get_os_typespec()) OSPV_fatindex2_cs(this); }

OSPV_fatindex2_cs::OSPV_fatindex2_cs(OSPV_fatindex2 *_at)
{
  init_tc(&tc);
  if (can_update(_at)) _at->REF_inc();
  tc_refocus(&tc, &_at->tv);
  myfocus = _at;
}

OSPV_fatindex2_cs::~OSPV_fatindex2_cs()
{
  if (can_update(myfocus)) myfocus->REF_dec();
  free_tc(&tc);
}

OSSVPV *OSPV_fatindex2_cs::focus()
{ return myfocus; }

void OSPV_fatindex2_cs::moveto(I32 xto)
{ tc_moveto(&tc, xto); }
void OSPV_fatindex2_cs::step(I32 delta)
{ tc_step(&tc, delta); }
I32 OSPV_fatindex2_cs::pos()
{ return tc_pos(&tc); }

void OSPV_fatindex2_cs::keys()
{
  OSSVPV *pv;
  dOSP;
  if (dex2tc_fetch(&tc, &pv)) {
    SV *keys[DEXTV_MAXKEYS];
    OSPV_Generic *conf = (OSPV_Generic *) myfocus->conf_slot;
    OSPV_Generic *paths = (OSPV_Generic*) (conf)->avx(2)->get_ospv();
    int keycnt = paths->_count();
    for (int kx=0; kx < keycnt; kx++) {
      keys[kx] = osp->ossv_2sv(OSPV_Generic::path_2key(pv, (OSPV_Generic*) paths->avx(kx)->get_ospv()));
    }
    dSP;
    EXTEND(SP, keycnt);
    for (kx=0; kx < keycnt; kx++) {
      PUSHs(keys[kx]);
    }
    PUTBACK;
  }
}

int OSPV_fatindex2_cs::seek(SV **top, int items)
{
  OSPV_Generic *conf = (OSPV_Generic *) myfocus->conf_slot;
  OSPV_Generic *paths = (OSPV_Generic*) (conf)->avx(2)->get_ospv();
  int keycnt = paths->_count() < items-1 ? paths->_count() : items-1;
  if (keycnt <= 0) return 0;
  OSSV tmpkeys[DEXTV_MAXKEYS];
  OSSV *keys[DEXTV_MAXKEYS];
  OSPV_Generic *pcache[DEXTV_MAXKEYS];
  for (int xa=0; xa < keycnt; xa++) {
    tmpkeys[xa] = top[xa+1];
    keys[xa] = &tmpkeys[xa];
    pcache[xa] = (OSPV_Generic*) paths->avx(xa)->get_ospv();
  }
  int unique = conf->avx(1)->istrue();
  return dex2tc_seek(&tc, unique, keycnt, pcache, keys);
}

void OSPV_fatindex2_cs::at()
{
  OSSVPV *pv;
  dOSP;
  if (dex2tc_fetch(&tc, &pv)) {
    SV *ret = osp->ospv_2sv(pv);
    dSP;
    XPUSHs(ret);
    PUTBACK;
  }
}

MODULE = ObjStore::REP::FatTree		PACKAGE = ObjStore::REP::FatTree

BOOT:
  HV *avrep = perl_get_hv("ObjStore::AV::REP", TRUE);
  hv_store(avrep, "ObjStore::REP::FatTree::AV", 26, newSViv(1), 0);
  HV *xvrep = perl_get_hv("ObjStore::Index::REP", TRUE);
  hv_store(xvrep, "ObjStore::REP::FatTree::Index", 29, newSViv(1), 0);
  HV *szof = perl_get_hv("ObjStore::sizeof", TRUE);
  //hv_store(szof, "tn0", 3, newSViv(sizeof(tn0)), 0);
  hv_store(szof, "OSPV_fattree_av", 15, newSViv(sizeof(OSPV_fattree_av)), 0);
  hv_store(szof, "avtn", 4, newSViv(sizeof(avtn)), 0);
  hv_store(szof, "OSPV_fatindex2", 14, newSViv(sizeof(OSPV_fatindex2)), 0);
  hv_store(szof, "dex2tn", 6, newSViv(sizeof(dex2tn)), 0);

MODULE = ObjStore::REP::FatTree		PACKAGE = ObjStore::REP::FatTree::AV

static void
OSPV_fattree_av::new(seg, sz)
	SV *seg;
	int sz;
	PPCODE:
	dOSP;
	SV *CSV = ST(0);
	os_segment *area = osp->sv_2segment(ST(1));
	PUTBACK;
	if (sz < 40) {
	  SERIOUS("ObjStore::REP::FatTree::AV->new(%d): representation not efficient for small arrays", sz);
	}
	OSPV_fattree_av *pv = new(area, OSPV_fattree_av::get_os_typespec()) OSPV_fattree_av();
	init_tv(&pv->ary);
	pv->bless(CSV);
	return;

MODULE = ObjStore::REP::FatTree		PACKAGE = ObjStore::REP::FatTree::Index

static void
OSPV_fatindex2::new(seg)
	SV *seg;
	PPCODE:
	dOSP;
	os_segment *area = osp->sv_2segment(ST(1));
	PUTBACK;
	OSPV_fatindex2 *pv = new(area, OSPV_fatindex2::get_os_typespec()) OSPV_fatindex2();
	init_tv(&pv->tv);
	pv->bless(ST(0));
	return;

void
OSPV_fatindex2::_conf_slot(...)
	PPCODE:
	PUTBACK;
	SV *ret = 0;
	if (items == 2) {
	  if (TvFILL(&THIS->tv)) {
	    croak("Configuration of an active index cannot be changed");
	  }
	  ossv_bridge *br = osp->sv_2bridge(ST(1), 1, os_segment::of(THIS));
	  OSSVPV *nconf = br->ospv();
	  nconf->REF_inc();
	  if (THIS->conf_slot) THIS->conf_slot->REF_dec();
	  THIS->conf_slot = nconf;
	} else if (items == 1) {
	  ret = osp->ospv_2sv(THIS->conf_slot);
	} else {
	  croak("OSPV_fatindex2(%p)->_conf_slot: bad args", THIS);
	}
	SPAGAIN;
	if (ret) XPUSHs(ret);
