// Switch to -*-c++-*- mode please!
/*
Copyright (c) 1997 Joshua Nathaniel Pritikin.  All rights reserved.
This package is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.
*/

#include "osperl.h"
#include <ostore/coll.hh>

/*--------------------------------------------- typemap services */

os_segment *osp_thr::sv_2segment(SV *sv)
{
  if (sv_isa(sv, "ObjStore::Segment")) return (os_segment*) SvIV((SV*)SvRV(sv));
  croak("sv_2segment only accepts ObjStore::Segment");
}

ossv_bridge *osp_thr::sv_2bridge(SV *ref, int force, os_segment *seg)
{
  dOSP ;
// Is tied?  Examine tied object, extract ossv_bridge from '~'
// Is OSSV in a PVMG?

  assert(ref);
  if (!SvROK(ref)) {
    if (force) croak("sv_2bridge: expecting a reference");
    return 0;
  }
  SV *nval = SvRV(ref);
  assert(nval);

  ossv_bridge *br = 0;
  do {
    if (SvMAGICAL(nval) && (SvTYPE(nval) == SVt_PVHV ||
			    SvTYPE(nval) == SVt_PVAV)) {
      MAGIC *magic = mg_find(nval, '~');
      if (!magic) break;
      SV *mgobj = (SV*) magic->mg_obj;
      if (!SvROK(mgobj)) break;
      br = (ossv_bridge*) SvIV((SV*)SvRV(mgobj));
    } else if (SvROK(nval)) {
      nval = SvRV(nval);
      if (SvOBJECT(nval) && SvTYPE(nval) == SVt_PVMG) {
	br = (ossv_bridge*) SvIV(nval);
      }
    }
  } while (0);

  if (br) return br;
  if (!force) return 0;
  if (!seg) croak("sv_2bridge: expecting a persistent object");
  
  dSP ;
  PUSHMARK(sp);
  XPUSHs(sv_setref_pv(sv_newmortal(), "ObjStore::Segment", seg));
  XPUSHs(ref);
  PUTBACK ;
  assert(osp->stargate);
  int count = perl_call_sv(osp->stargate, G_SCALAR);
  assert(count==1);
  SPAGAIN ;
  br = osp->sv_2bridge(POPs, 0);
  PUTBACK ;
  if (!br) croak("ObjStore::stargate: returned useless junk");
  //  warn("stargate returned:");
  //  br->dump();
  return br;
}

// Why does _new_bridge get passed itself twice?  Could this be a mistake?  XXX

static SV *ospv_2bridge(OSSVPV *pv)
{
  ossv_bridge *br = pv->_new_bridge(pv);
  SV *rv = sv_setref_pv(sv_newmortal(), "ObjStore::Bridge", (void*)br);
  return rv;
}

SV *osp_thr::wrap(OSSVPV *ospv, SV *br)
{
  dOSP ;
  STRLEN CLEN;
  char *CLASS = ospv->blessed_to(&CLEN);

  switch (ospv->get_perl_type()) {
  case SVt_PVMG:{
    SV *rv = newRV_noinc(br);
    HV* stash = gv_stashpvn(CLASS, CLEN, TRUE);	// bless $rv, CLASS
    assert(stash);
    (void)sv_bless(rv, stash);
    DEBUG_wrap(warn("mgwrap %p", ospv); sv_dump(br););
    return rv;}
  case SVt_PVHV:
  case SVt_PVAV:{
    // This typemap scares me.  Will it work consistently? XXX
      SV *tied;
      if (ospv->get_perl_type() == SVt_PVHV) {
	tied = sv_2mortal((SV*) newHV());	// %tied
      } else {
	tied = sv_2mortal((SV*) newAV());	// @tied
      }
      sv_magic(tied, br, '~', Nullch, 0);	// magic tied, '~', $mgobj
      SV *rv = newRV_noinc(tied);		// $rv = \tied

      if (osp->tie_objects) {
	sv_magic(tied, rv, 'P', Nullch, 0);	// tie tied, CLASS, $rv
	MAGIC *tie_mg = mg_find(tied, 'P');	// undo tie refcnt (yikes!)
	assert(tie_mg);
	tie_mg->mg_flags &= ~(MGf_REFCOUNTED);
	--SvREFCNT(rv);
      }

      HV* stash = gv_stashpvn(CLASS, CLEN, TRUE); // bless $rv, CLASS
      assert(stash);
      (void)sv_bless(rv, stash);
      
      DEBUG_wrap(warn("[av]wrap %p", ospv); sv_dump(rv););
      return rv;}
  default:
      croak("osp::ossv_2sv: unknown perl type (%d)", ospv->get_perl_type());
  }
  return 0;
}

SV *osp_thr::ospv_2sv(OSSVPV *pv)
{
  if (!pv) return &sv_undef;
  return wrap(pv, ospv_2bridge(pv));
}

//    if (GIMME_V == G_VOID) return 0;  // fold into ossv_2sv? XXX
SV *osp_thr::ossv_2sv(OSSV *ossv)
{
  if (!ossv) return &sv_undef;
  switch (ossv->natural()) {
  case ossv_undef: return &sv_undef;
  case ossv_xiv:   return newSViv(ossv->xiv);
  case ossv_iv:
    //    assert(ossv->vptr);
    if (!ossv->vptr) return &sv_undef;
    return newSViv(((OSPV_iv*)ossv->vptr)->iv);
  case ossv_nv:
    //    assert(ossv->vptr);
    if (!ossv->vptr) return &sv_undef;
    return newSVnv(((OSPV_nv*)ossv->vptr)->nv);
  case ossv_pv:
    //    assert(ossv->vptr);
    if (!ossv->vptr) return &sv_undef;
    return newSVpv((char*) ossv->vptr, ossv->xiv);
  case ossv_obj:{
    //    assert(ossv->vptr);
    if (!ossv->vptr) return &sv_undef;
    OSSVPV *pv = (OSSVPV*) ossv->vptr;
    return wrap(pv, ospv_2bridge(pv));
  }
  default:
    warn("OSSV %s is not implemented", ossv->type_2pv());
    return &sv_undef;
  }
}

void osp_thr::push_ospv(OSSVPV *pv)
{
  dOSP ;
  if (!pv) return;
  SV *sv = osp->ospv_2sv(pv);
  dSP;
  PUSHs(sv);
  PUTBACK;
}

OSSV *osp_thr::plant_ospv(os_segment *seg, OSSVPV *pv)
{
  assert(pv);
  OSSV *ossv = new(os_segment::of(pv), OSSV::get_os_typespec()) OSSV(pv);
  return ossv;
}

OSSV *osp_thr::plant_sv(os_segment *seg, SV *nval)
{
  dOSP ;
  OSSV *ossv=0;
  if (SvROK(nval)) {
    ossv_bridge *br = osp->sv_2bridge(nval, 1, seg);
    assert(br);
    OSSVPV *pv = br->ospv();
    assert(pv);
    ossv = new(os_segment::of(pv), OSSV::get_os_typespec()) OSSV(pv);
  } else {
    ossv = new(seg, OSSV::get_os_typespec()) OSSV(nval);
  }
  assert(ossv);
  return ossv;
}

/*--------------------------------------------- OSSV */

OSSV::OSSV() : _type(ossv_undef)
{}

OSSV::OSSV(SV *nval) : _type(ossv_undef)
{ this->operator=(nval); }

OSSV::OSSV(OSSV *nval) : _type(ossv_undef)
{ *this = *nval; }

OSSV::OSSV(OSSVPV *nval) : _type(ossv_undef)
{ s(nval); }

OSSV::~OSSV()
{ set_undef(); }

OSSVPV *OSSV::get_ospv()
{
  if (natural() != ossv_obj) croak("THIS=%s is not an object", type_2pv());
  assert(vptr);
  return (OSSVPV*)vptr;
}

int OSSV::PvREFok()
{ return natural() == ossv_obj; }

void OSSV::PvREF_inc(void *nval)
{
  assert (PvREFok());
  if (nval) vptr = nval;
  assert(vptr != 0);
  ((OSSVPV*)vptr)->REF_inc();
}

void OSSV::PvREF_dec()
{
  assert (PvREFok());
  ((OSSVPV*)vptr)->REF_dec();
  vptr = 0;
}

//assist C++ templates call undef (?) XXX
OSSV *OSSV::operator=(int zero)
{
  assert(zero == 0);
  set_undef();
  return this;
}

// Should always try to store numbers in the smallest space that
// preserves precision.  Is this right?  XXX
OSSV *OSSV::operator=(SV *nval)
{
  dOSP ;
  char *tmp; unsigned tmplen;

  if (SvROK(nval)) {
    dTHR;
    ENTER;
    SAVETMPS;
    s(osp->sv_2bridge(nval, 1, os_segment::of(this)));
    FREETMPS;
    LEAVE;
  } else if (SvIOKp(nval)) {
    s((os_int32) SvIV(nval));
  } else if (SvNOKp(nval)) {
    s((double) SvNV(nval));
  } else if (SvPOK(nval)) {
    tmp = SvPV(nval, tmplen);
    s(tmp, tmplen);
  } else if (! SvOK(nval)) {
    set_undef();
  } else {
    croak("OSSV=(SV*): unknown type");
  }
  return this;
}

OSSV *OSSV::operator=(const OSSV &nval)		// i hate const
{ s( (OSSV*) &nval); return this; }

OSSV *OSSV::operator=(OSSV &nval)
{ s(&nval); return this; }

int OSSV::operator==(OSSVPV *pv)
{
  if (natural() != ossv_obj) return 0;
  return vptr == pv;
}

ossvtype OSSV::natural() const
{ return (ossvtype) _type; }

int OSSV::is_set()
{ return _type != ossv_undef; }

// prepare to switch to new datatype
int OSSV::morph(ossvtype nty)
{
  if (_type == nty) return 0;

  if (PvREFok()) PvREF_dec();
  switch (_type) {
  case ossv_undef: break;
  case ossv_iv:    delete ((OSPV_iv*)vptr); vptr=0; break;
  case ossv_nv:    delete ((OSPV_nv*)vptr); vptr=0; break;

  case ossv_pv:
    DEBUG_assign(warn("OSSV(0x%x)->morph(pv): deleting string '%s' 0x%x",
		      this, vptr, vptr));
    delete [] ((char*)vptr);
    vptr = 0;
    break;

  case ossv_xiv: break;
  case ossv_obj: break;

  default: warn("OSSV(0x%p)->morph type %s unknown! (serious error)",
		this, OSSV::type_2pv( (ossvtype)_type));
  }
  _type = nty;
  return 1;
}

void OSSV::set_undef()
{ morph(ossv_undef); }

void OSSV::s(os_int32 nval)
{
  if (((os_int16) (nval & 0xffff)) == nval) {
    morph(ossv_xiv);
    xiv = nval;
    DEBUG_assign(warn("OSSV(0x%x)->s(%d:xi)", this, nval));
  } else {
    if (morph(ossv_iv)) {
      vptr = new(os_segment::of(this), OSPV_iv::get_os_typespec()) OSPV_iv;
    }
    ((OSPV_iv*)vptr)->iv = nval;
    DEBUG_assign(warn("OSSV(0x%x)->s(%d:i)", this, nval));
  }
}

void OSSV::s(double nval)
{
  register os_int32 i32_nval = nval;
  if (i32_nval == nval) {
    s(i32_nval);
  } else {
    if (morph(ossv_nv)) {
      vptr = new(os_segment::of(this), OSPV_nv::get_os_typespec()) OSPV_nv;
    }
    ((OSPV_nv*)vptr)->nv = nval;
    DEBUG_assign(warn("OSSV(0x%x)->s(%f:n)", this, nval));
  }
}

// nval must be null terminated or the length must be specified.
// Since the length is not stored, a null terminated is added if not found.
void OSSV::s(char *nval, os_unsigned_int32 nlen)
{
  assert(nlen > 0 || nval[0] == 0);
  if (nlen > 32767) {
    warn("String truncated to 32767 bytes");
    nlen = 32767;
  }
  xiv = nlen;
  if (!morph(ossv_pv)) {
    DEBUG_assign(warn("OSSV(0x%x)->s(): deleting string 0x%x", this, vptr));
    delete [] ((char*)vptr);
    vptr = 0;
  }
  char *str = new(os_segment::of(this), os_typespec::get_char(),
		  nlen) char[nlen];
  memcpy(str, nval, nlen);
  vptr = str;
  DEBUG_assign(warn("OSSV(0x%x)->s(%s): alloc 0x%x", this, (char*) vptr, str));
}

void OSSV::s(ossv_bridge *br)
{
  if (br->pv) { s(br->pv); return; }
  croak("OSSV::s(ossv_bridge*): assertion failed");
}

void OSSV::s(OSSV *nval)
{ 
  assert(nval);
  switch (nval->natural()) {
  case ossv_undef: set_undef(); break;
  case ossv_xiv:   s(nval->xiv); break;
  case ossv_iv:    s(((OSPV_iv*)nval->vptr)->iv); break;
  case ossv_nv:    s(((OSPV_nv*)nval->vptr)->nv); break;
  case ossv_pv:    s((char*) nval->vptr, nval->xiv); break;
  case ossv_obj:   s((OSSVPV*) nval->vptr); break;
  default:         croak("OSSV::s(OSSV*): assertion failed");
  }
}

void OSSV::s(OSSVPV *nval)
{ 
  assert(nval);
  STRLEN len;
  DEBUG_assign(warn("OSSV(0x%x)->s(%s=0x%x)", this, nval->os_class(&len), nval));
  if (morph(ossv_obj)) {
    PvREF_inc(nval);
  } else if (vptr != nval) {
    PvREF_dec();
    PvREF_inc(nval);
  }
}

char *OSSV::pv(STRLEN *len)
{
  assert(len);
  *len = xiv; return (char*) vptr;
}

char OSSV::strrep[64];
char *OSSV::stringify()
{
  switch (natural()) {
  case ossv_xiv:  sprintf(strrep, "%d", xiv); break;
  case ossv_iv:   sprintf(strrep, "%ld", ((OSPV_iv*)vptr)->iv); break;
  case ossv_nv:   sprintf(strrep, "%f", ((OSPV_nv*)vptr)->nv); break;
  case ossv_pv:{
    STRLEN len;
    char *s1 = pv(&len);
    if (len > 60) len = 60;
    memcpy(strrep, s1, len);
    strrep[len]=0;
    break;}
  case ossv_obj:
    sprintf(strrep, "OBJECT(0x%p)", vptr);
    break;
  default:
    warn("SV %s has no string representation", type_2pv());
    strrep[0]=0;
    break;
  }
  return strrep;
}

char *OSSV::type_2pv(ossvtype ty)
{
  switch (ty) {
   case ossv_undef: return "undef";
   case ossv_xiv:   return "int";
   case ossv_iv:    return "int";
   case ossv_nv:    return "double";
   case ossv_pv:    return "string";
   case ossv_obj:    return "OBJECT";
   default:
     sprintf(strrep, "ossv(%d)", ty);
     return strrep;
  }
};

char *OSSV::type_2pv()
{
  switch (natural()) {
   case ossv_undef: return "undef";
   case ossv_xiv:   return "int";
   case ossv_iv:    return "int";
   case ossv_nv:    return "double";
   case ossv_pv:    return "string";
   case ossv_obj:
     sprintf(strrep, "OBJECT(0x%p)", vptr);
     return strrep;
   default:
     sprintf(strrep, "ossv(%d)", natural());
     return strrep;
  }
}

/*--------------------------------------------- OSSVPV */

OSSVPV::OSSVPV()
  : _refs(0), _weak_refs(0), classname(0)
{
  DEBUG_refcnt(warn("new OSSVPV(0x%x)", this));
}
OSSVPV::~OSSVPV()
{
  DEBUG_refcnt(warn("~OSSVPV(0x%x)", this));
  if (PvBLESS2(this) && classname) ((OSSVPV*)classname)->REF_dec();
}

// C++ API for perl 'bless'
void OSSVPV::bless(SV *stash)
{
  DEBUG_bless(warn("0x%x->bless('%s')", this, SvPV(stash, na)));
  dOSP;
  SV *me = osp->ospv_2sv(this);
  dSP;
  // We must avoid the user-level bless if possible since the our
  // bless glue creates persistent objects.
  STRLEN cur1, cur2;
  char *pv1 = SvPV(stash, cur1);
  char *pv2 = os_class(&cur2);
  if (memcmp((void*)pv1, (void*)pv2, cur1 < cur2 ? cur1 : cur2)== 0 &&
      cur1 == cur2) {
    // Can avoid storing the bless-to for 'unblessed' objects.
    XPUSHs(me);
    PUTBACK;
    return;
  }
  PUSHMARK(SP);
  XPUSHs(me);
  XPUSHs(sv_2mortal(newSVsv(stash)));
  PUTBACK;
  perl_call_pv("ObjStore::bless", G_SCALAR);
}

int OSSVPV::_is_blessed()
{ return classname != 0; }

char *OSSVPV::blessed_to(STRLEN *CLEN)
{
  // MUST BE FAST
  dOSP;
  char *CLASS=0;

  if (classname) {
    if (PvBLESS2(this)) {
      OSPV_Generic *av = (OSPV_Generic*)classname;
      assert(av);
      OSSV *str = av->FETCHi(1);
      assert(str && str->natural() == ossv_pv);
      CLASS = str->pv(CLEN);
    } else {
      CLASS = (char*) classname;
      *CLEN = strlen(CLASS);
    }
  }
  // CLASS must be null terminated!

  if (CLASS) {
    // roll up into database open! XXX
    SV *toclass=0;
    SV **msvp = hv_fetch(osp->CLASSLOAD, CLASS, *CLEN, 0); //in CACHE?
    if (msvp) toclass = *msvp;

    if (!toclass || !SvPOK(toclass)) {		// load and add to CACHE
      // CAN BE SLOW
      STRLEN len;
      char *oscl = os_class(&len);
      if (len != strlen(oscl)) die("os_class(): length of %s is wrong", oscl);
      SV *ldr = perl_get_sv("ObjStore::CLASSLOAD", 0);
      assert(ldr);
      dSP;
      ENTER;
      SAVETMPS;
      PUSHMARK(SP);
      EXTEND(SP, 3);
      PUSHs(sv_2mortal(newSVpv("The database should not be considered", 0)));
      PUSHs(sv_2mortal(newSVpv(oscl, len)));
      PUSHs(sv_2mortal(newSVpv(CLASS, *CLEN)));
      PUTBACK;
      int count = perl_call_sv(ldr, G_SCALAR);
      if (SvTRUE(GvSV(errgv))) {
	croak("$ObjStore::CLASSLOAD: $@='%s' (bogus)", SvPV(GvSV(errgv), na));
      }
      if (count != 1) {
	croak("$ObjStore::CLASSLOAD: got %d args in scalar context", count);
      }
      SPAGAIN;
      toclass = POPs;
      if (!SvPOK(toclass)) croak("$ObjStore::CLASSLOAD did not return a string");
      SvREFCNT_inc(toclass);
      hv_store(osp->CLASSLOAD, CLASS, *CLEN, toclass, 0);
      PUTBACK;
      FREETMPS;
      LEAVE;
    }

    CLASS = SvPV(toclass, *CLEN);
  }
  if (!CLASS) { CLASS = os_class(CLEN); }
  return CLASS;
}

static const os_unsigned_int32 REFCNT32 = 4294967285UL;    // 2**32 - 10
static const os_unsigned_int32 REFCNT16 = 65526;           // 2**16 - 10
void OSSVPV::REF_inc() {
  _refs++;
  if (_refs > REFCNT32) croak("OSSVPV::REF_inc(): _refs > %ud", REFCNT32);
  DEBUG_refcnt(warn("OSSVPV(0x%x)->REF_inc() to %d/%d", this, _refs,_weak_refs));
}

void OSSVPV::REF_dec() { 
  if (_refs == 0) croak("%p->REF_dec to -1", this);
  if (_refs == 1 && classname != 0 && !PvINUSE(this)) {
    PvINUSE_on(this); //protect from race condition
    DEBUG_refcnt(warn("%x->enter NOREFS", this));
    dOSP;
    STRLEN bslen;
    char *bs = blessed_to(&bslen);
    // cache last lookup to avoid gv_fetchmethod XXX
    SV *meth=0;
    HV *pkg = gv_stashpvn(bs, bslen, 0);
    if (pkg)
      meth = (SV*) gv_fetchmethod(pkg, "NOREFS");
    if (meth) {
      SV *br = ospv_2bridge(this);
      SV *me = osp->wrap(this, br);
      dSP;
      PUSHMARK(SP);
      XPUSHs(me);
      PUTBACK;
      perl_call_sv(meth, G_VOID|G_DISCARD);
      ((ossv_bridge*) SvIV(SvRV(br)))->invalidate(); //must avoid extra ref!
    }
    
    DEBUG_refcnt(warn("%x->exit NOREFS", this));
    PvINUSE_off(this);
  }
  _refs--;
  DEBUG_refcnt(warn("OSSVPV(0x%x)->REF_dec() to %d/%d", this, _refs,_weak_refs));
  if (_refs + _weak_refs == 0) {
    DEBUG_refcnt(warn("%x: begin delete", this));
    delete this;
    DEBUG_refcnt(warn("%x: finish delete", this));
  }
}

/*
void OSSVPV::wREF_inc() {
  _weak_refs++;
  if (_refs > REFCNT16) croak("OSSVPV::REF_inc(): _weak_refs > %ud", REFCNT16);
  DEBUG_refcnt(warn("OSSVPV(0x%x)->wREF_inc() to %d/%d",this,_refs,_weak_refs));
}

void OSSVPV::wREF_dec() { 
  if (_weak_refs==0) return;  // weak_refs can be inaccurate
  _weak_refs--;
  DEBUG_refcnt(warn("OSSVPV(0x%x)->wREF_dec() to %d/%d",this,_refs,_weak_refs));
  if (_refs + _weak_refs == 0) delete this;
}
*/

int OSSVPV::get_perl_type()
{ return SVt_PVMG; }

char *OSSVPV::os_class(STRLEN *)
{ croak("OSSVPV(0x%x)->os_class() must be overridden", this); return 0; }

// Usually will override, but here's a default.
ossv_bridge *OSSVPV::_new_bridge(OSSVPV *_pv)
{ return new ossv_bridge(_pv); }

// common to containers
void OSPV_Container::install_rep(HV *hv, const char *file, char *name, XS_t mk)
{
  SV *rep = (SV*) newXS(0, mk, (char*) file);
  sv_setpv(rep, "$$$");
  hv_store(hv, name, strlen(name), newRV(rep), 0);
}

double OSPV_Container::_percent_filled()
{ return -1; }
int OSPV_Container::_count()
{ STRLEN ign; croak("%s->_count not implemented", os_class(&ign)); return 0; }
OSPV_Cursor *OSPV_Container::new_cursor(os_segment *seg)
{ STRLEN ign; croak("%s->new_cursor not implemented", os_class(&ign)); return 0; }

/*--------------------------------------------- GENERIC */

SV *OSPV_Generic::FIRST(ossv_bridge*) { croak("OSSVPV(0x%x)->FIRST",this); return 0; }
SV *OSPV_Generic::NEXT(ossv_bridge*) { croak("OSSVPV(0x%x)->NEXT",this); return 0; }
void OSPV_Generic::CLEAR() { croak("OSSVPV(0x%x)->CLEAR",this); }

// hash
SV *OSPV_Generic::FETCHp(char *) { croak("OSSVPV(0x%x)->FETCHp",this); return 0; }
SV *OSPV_Generic::STOREp(char *, SV *) { croak("OSSVPV(0x%x)->STOREp",this); return 0; }
void OSPV_Generic::DELETE(char *) { croak("OSSVPV(0x%x)->DELETE",this); }
int OSPV_Generic::EXISTS(char *) { croak("OSSVPV(0x%x)->EXISTS",this); return 0; }

// set (depreciated)
void OSPV_Generic::add(SV *) { croak("OSSVPV(0x%x)->add",this); }
int OSPV_Generic::contains(SV *) { croak("OSSVPV(0x%x)->contains",this); return 0; }
void OSPV_Generic::rm(SV *) { croak("OSSVPV(0x%x)->rm",this); }

// array (preliminary)
OSSV *OSPV_Generic::FETCHi(int) { croak("OSSVPV(0x%x)->FETCHi", this); return 0; }
OSSV *OSPV_Generic::STOREi(int, SV *) { croak("OSSVPV(0x%x)->STOREi",this); return 0; }
int OSPV_Generic::_LENGTH() {croak("OSSVPV(0x%x)->_LENGTH",this); return 0; }
SV *OSPV_Generic::Pop() {croak("OSSVPV(0x%x)->Pop",this); return 0; }
SV *OSPV_Generic::Unshift() {croak("OSSVPV(0x%x)->Unshift",this); return 0; }
void OSPV_Generic::Push(SV *) {croak("OSSVPV(0x%x)->Push",this); }
void OSPV_Generic::Shift(SV *) {croak("OSSVPV(0x%x)->Shift",this); }

// REFERENCES
OSPV_Ref2::OSPV_Ref2()
{}
char *OSPV_Ref2::os_class(STRLEN *len)
{ *len = 13; return "ObjStore::Ref"; }
os_database *OSPV_Ref2::get_database()
{ croak("OSPV_Ref2::get_database()"); return 0; }
char *OSPV_Ref2::dump()
{ croak("OSPV_Ref::dump()"); return 0; }
OSSVPV *OSPV_Ref2::focus()
{ croak("OSPV_Ref::focus()"); return 0; }
int OSPV_Ref2::deleted()
{ croak("OSPV_Ref2(%p)->deleted(): unsupported on this type of ref", this); return 0; }

// protected reference
OSPV_Ref2_protect::OSPV_Ref2_protect(OSSVPV *pv) : myfocus(pv)
{}
OSPV_Ref2_protect::OSPV_Ref2_protect(char *dump, os_database *db)
{ myfocus.load(dump, db); }
os_database *OSPV_Ref2_protect::get_database()
{ return myfocus.get_database(); }
int OSPV_Ref2_protect::deleted()
{ return myfocus.deleted() || focus()->_refs == 0; }
char *OSPV_Ref2_protect::dump()
{ return myfocus.dump(); }
OSSVPV *OSPV_Ref2_protect::focus()
{ return (OSSVPV*) myfocus.resolve(); }

// hard reference
OSPV_Ref2_hard::OSPV_Ref2_hard(OSSVPV *pv) : myfocus(pv)
{}
OSPV_Ref2_hard::OSPV_Ref2_hard(char *dump, os_database *db)
{ myfocus.load(dump, db); }
os_database *OSPV_Ref2_hard::get_database()
{ return myfocus.get_database(); }
int OSPV_Ref2_hard::deleted()  //only during NOREFS
{ return focus()->_refs == 0; }
char *OSPV_Ref2_hard::dump()
{ return myfocus.dump(); }
OSSVPV *OSPV_Ref2_hard::focus()
{ return (OSSVPV*) myfocus.resolve(); }


// CURSORS
OSPV_Cursor2::OSPV_Cursor2(OSSVPV *)
{ croak("OSPV_Cursor2::OSPV_Cursor2(OSSVPV *)"); }
char *OSPV_Cursor2::os_class(STRLEN *len)
{ *len = 16; return "ObjStore::Cursor"; }

void OSPV_Cursor2::seek_pole(int)
{ croak("OSPV_Cursor(0x%x)->seek_pole()", this); }
void OSPV_Cursor2::at()
{ croak("OSPV_Cursor(0x%x)->at()", this); }
void OSPV_Cursor2::next()
{ croak("OSPV_Cursor(0x%x)->next()", this); }

//////////////////////////////////////////////////////////////////////
// DEPRECIATED
OSPV_Ref::OSPV_Ref(OSSVPV *_at) : myfocus(_at)
{}

OSPV_Ref::OSPV_Ref(char *dump, os_database *db)
{ myfocus.load(dump, db); }

OSPV_Ref::~OSPV_Ref()
{}

char *OSPV_Ref::os_class(STRLEN *len)
{ *len = 26; return "ObjStore::DEPRECIATED::Ref"; }

os_database *OSPV_Ref::get_database()
{ return myfocus.get_database(); }

char *OSPV_Ref::dump()
{ return myfocus.dump(); }

int OSPV_Ref::deleted()
{ return myfocus.deleted() || focus()->_refs == 0; }

OSSVPV *OSPV_Ref::focus()
{ return (OSSVPV*) myfocus.resolve(); }

// CURSORS
OSPV_Cursor::OSPV_Cursor(OSSVPV *_at) : OSPV_Ref(_at)
{}

char *OSPV_Cursor::os_class(STRLEN *len)
{ *len = 16; return "ObjStore::Cursor"; }

void OSPV_Cursor::seek_pole(int)
{ croak("OSPV_Cursor(0x%x)->seek_pole()", this); }
void OSPV_Cursor::at()
{ croak("OSPV_Cursor(0x%x)->at()", this); }
void OSPV_Cursor::next()
{ croak("OSPV_Cursor(0x%x)->next()", this); }
