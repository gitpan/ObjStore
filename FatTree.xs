// -*-C++-*- mode
#include "osperl.h"
#include "FatTree.h"
#include "XSthr.h"

static const char *file = __FILE__;

struct FatTree_thr {
  dexXPVTC tc;
};
static FatTree_thr *construct_thr()
{
  FatTree_thr *ti = new FatTree_thr;
  dexinit_tc(&ti->tc);
  return ti;
}
static void destory_thr(FatTree_thr *ti)
{
  ti->tc.xtc_tv = 0;
  dexfree_tc(&ti->tc);
}
dTHRINIT(FatTree, construct_thr, destroy_thr);

//--------------------------- ---------------------------

XS(XS_ObjStore__REP__FatTree__Index_new);

OSPV_fatindex::OSPV_fatindex()
{ dexinit_tv(&fi_tv); conf_slot=0; }

OSPV_fatindex::~OSPV_fatindex()
{
  CLEAR(); 
  dexfree_tv(&fi_tv);
  if (conf_slot) conf_slot->REF_dec();
}

char *OSPV_fatindex::os_class(STRLEN *len)
{ *len = 15; return "ObjStore::Index"; }

char *OSPV_fatindex::rep_class(STRLEN *len)
{ *len = 29; return "ObjStore::REP::FatTree::Index"; }

int OSPV_fatindex::get_perl_type()
{ return SVt_PVAV; }

void OSPV_fatindex::CLEAR()
{
  if (conf_slot) {
    OSPV_Generic *conf = (OSPV_Generic *) conf_slot;
    assert(conf->is_array());
    OSPV_Generic *paths = (OSPV_Generic*) conf->FETCHi(2)->get_ospv();
    dDEXTMPCURSOR(this);
    dextc_moveto(&gl->tc, 0);
    OSSVPV *pv;
    while (dextc_fetch(&gl->tc, &pv)) {
      osp_pathexam exam(paths, pv, 'u');
      pv->REF_dec();
      dextc_step(&gl->tc, 1);
    }
  }
  dextv_clear(&fi_tv);
}

void OSPV_fatindex::add(OSSVPV *obj)
{
  assert(conf_slot);
  OSPV_Generic *conf = (OSPV_Generic *) conf_slot;
  dDEXTMPCURSOR(this);
  assert(conf->is_array());
  OSPV_Generic *paths = (OSPV_Generic*) (conf)->FETCHi(2)->get_ospv();
  osp_pathexam exam(paths, obj, 's');
  int match = dextc_seek(&gl->tc, exam.keycnt, exam.pcache, exam.keys);
  if (match && conf->FETCHi(1)->istrue()) {
    OSSVPV *here;
    dextc_fetch(&gl->tc, &here);
    if (here == obj) return;
    exam.abort();
    croak("%p->add(): attempt to insert duplicate record into a unique index",this);
  }
  obj->REF_inc();
  dextc_insert(&gl->tc, &obj);
}

void OSPV_fatindex::remove(OSSVPV *target)
{
  dDEXTMPCURSOR(this);
  OSPV_Generic *conf = (OSPV_Generic *) conf_slot;
  OSPV_Generic *paths = (OSPV_Generic*) conf->FETCHi(2)->get_ospv();
  osp_pathexam exam(paths, target, 'u');
  dextc_seek(&gl->tc, exam.keycnt, exam.pcache, exam.keys);
  OSSVPV *obj;
  while (dextc_fetch(&gl->tc, &obj)) {
    if (obj == target) {
      dextc_delete(&gl->tc);
      target->REF_dec();
      return;
    }
    // Might step through a large number of records; no choice.
    dextc_step(&gl->tc, 1);
  }
  croak("%p->remove(%p): record not found", this, target);
}

OSSVPV *OSPV_fatindex::FETCHx(int xx)
{
  dDEXTMPCURSOR(this);
  dextc_moveto(&gl->tc, xx);
  OSSVPV *pv=0;
  dextc_fetch(&gl->tc, &pv);
  return pv;
}

double OSPV_fatindex::_percent_filled()
{ return dexTvFILL(&fi_tv) / (double) dexTvMAX(&fi_tv); }
int OSPV_fatindex::_count()
{ return dexTvFILL(&fi_tv); }

OSSVPV *OSPV_fatindex::new_cursor(os_segment *seg)
{ return new(seg, OSPV_fatindex_cs::get_os_typespec()) OSPV_fatindex_cs(this); }

OSPV_fatindex_cs::OSPV_fatindex_cs(OSPV_fatindex *_at)
{
  dexinit_tc(&fi_tc);
  if (os_segment::of(this) == os_segment::of(0)) {
    dOSP; dTXN;
    if (txn->can_update()) _at->REF_inc();
  } else {
    _at->REF_inc();
  }
  fi_tc.xtc_tv = _at;
}

OSPV_fatindex_cs::~OSPV_fatindex_cs()
{
  if (os_segment::of(this) == os_segment::of(0)) {
    dOSP; dTXN;
    if (txn->can_update()) TcOSPV(&fi_tc)->REF_dec();
  } else {
    TcOSPV(&fi_tc)->REF_dec();
  }
  dexfree_tc(&fi_tc);
}

OSSVPV *OSPV_fatindex_cs::focus()
{ return fi_tc.xtc_tv; }

void OSPV_fatindex_cs::moveto(I32 xto)
{ dextc_moveto(&fi_tc, xto); }
void OSPV_fatindex_cs::step(I32 delta)
{ dextc_step(&fi_tc, delta); }
I32 OSPV_fatindex_cs::pos()
{ return dextc_pos(&fi_tc); }

void OSPV_fatindex_cs::keys()
{
  OSSVPV *pv;
  dOSP;
  if (dextc_fetch(&fi_tc, &pv)) {
    SV *keys[DEXTV_MAXKEYS];
    OSPV_Generic *conf = (OSPV_Generic *) TcOSPV(&fi_tc)->conf_slot;
    OSPV_Generic *paths = (OSPV_Generic*) (conf)->FETCHi(2)->get_ospv();
    int keycnt = paths->_count();
    for (int kx=0; kx < keycnt; kx++) {
      keys[kx] = osp->ossv_2sv(OSPV_Generic::path_2key(pv, (OSPV_Generic*) paths->FETCHi(kx)->get_ospv()));
    }
    dSP;
    EXTEND(SP, keycnt);
    for (kx=0; kx < keycnt; kx++) {
      PUSHs(keys[kx]);
    }
    PUTBACK;
  }
}

int OSPV_fatindex_cs::seek(SV **top, int items)
{
  OSPV_Generic *conf = (OSPV_Generic *) TcOSPV(&fi_tc)->conf_slot;
  OSPV_Generic *paths = (OSPV_Generic*) (conf)->FETCHi(2)->get_ospv();
  int keycnt = paths->_count() < items-1 ? paths->_count() : items-1;
  if (keycnt <= 0) return 0;
  OSSV tmpkeys[DEXTV_MAXKEYS];
  OSSV *keys[DEXTV_MAXKEYS];
  OSPV_Generic *pcache[DEXTV_MAXKEYS];
  for (int xa=0; xa < keycnt; xa++) {
    tmpkeys[xa] = top[xa+1];
    keys[xa] = &tmpkeys[xa];
    pcache[xa] = (OSPV_Generic*) paths->FETCHi(xa)->get_ospv();
  }
  return dextc_seek(&fi_tc, keycnt, pcache, keys);
}

void OSPV_fatindex_cs::at()
{
  OSSVPV *pv;
  dOSP;
  if (dextc_fetch(&fi_tc, &pv)) {
    SV *ret = osp->ospv_2sv(pv);
    dSP;
    XPUSHs(ret);
    PUTBACK;
  }
}

MODULE = ObjStore::REP::FatTree		PACKAGE = ObjStore::REP::FatTree

BOOT:
  SV *rep;
  HV *xvrep = perl_get_hv("ObjStore::Index::REP", TRUE);
  hv_store(xvrep, "ObjStore::REP::FatTree", 22, newSViv(1), 0);

MODULE = ObjStore::REP::FatTree		PACKAGE = ObjStore::REP::FatTree::Index

static void
OSPV_fatindex::new(seg)
	SV *seg;
	PPCODE:
	dOSP;
	os_segment *area = osp->sv_2segment(ST(1));
	PUTBACK;
	OSPV_fatindex *pv = new(area, OSPV_fatindex::get_os_typespec()) OSPV_fatindex();
	dexinit_tv(&pv->fi_tv);
	pv->bless(ST(0));
	return;

void
OSPV_fatindex::_conf_slot(...)
	PPCODE:
	PUTBACK;
	SV *ret = 0;
	if (items == 2) {
	  if (dexTvFILL(&THIS->fi_tv)) {
	    croak("Cannot change the configuration of an active index");
	  }
	  ossv_bridge *br = osp->sv_2bridge(ST(1), 1, os_segment::of(THIS));
	  OSSVPV *nconf = br->ospv();
	  nconf->REF_inc();
	  if (THIS->conf_slot) THIS->conf_slot->REF_dec();
	  THIS->conf_slot = nconf;
	} else if (items == 1) {
	  ret = osp->ospv_2sv(THIS->conf_slot);
	} else {
	  croak("OSPV_fatindex(%p)->_conf_slot: bad args", THIS);
	}
	SPAGAIN;
	if (ret) XPUSHs(ret);
