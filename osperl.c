// Switch to -*-c++-*- mode please!
// Copyright © 1997-1998 Joshua Nathaniel Pritikin.  All rights reserved.

#include "osperl.h"
#include <ostore/coll.hh>

/*--------------------------------------------- typemap services */

os_segment *osp_thr::sv_2segment(SV *sv)
{
  if (sv_isa(sv, "ObjStore::Segment")) return (os_segment*) SvIV((SV*)SvRV(sv));
  osp_croak("sv_2segment only accepts ObjStore::Segment");
}

ossv_bridge *osp_thr::sv_2bridge(SV *ref, int force, os_segment *seg)
{
  dOSP ;
// Is tied?  Examine tied object, extract ossv_bridge from '~'
// Is OSSV in a PVMG?

  if (SvGMAGICAL(ref))
    mg_get(ref);        //? XXX

  assert(ref);
  if (!SvROK(ref)) {
    if (force) osp_croak("sv_2bridge: expecting a reference");
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
  if (!seg) osp_croak("sv_2bridge: expecting a persistent object");
  
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
  if (!br) osp_croak("ObjStore::stargate: returned useless junk");
  //  warn("stargate returned:");
  //  br->dump();
  return br;
}

static SV *ospv_2bridge(OSSVPV *pv)
{
  SV *rv = sv_setref_pv(newSViv(0),
			"ObjStore::Bridge", 
			(void*)pv->new_bridge());
  return rv;
}

SV *osp_thr::wrap(OSSVPV *ospv, SV *br)
{
  dOSP ;
  HV *stash = ospv->stash();
  assert(stash);

  switch (ospv->get_perl_type()) {
  case SVt_PVMG:{
    SV *rv = sv_2mortal(newRV_noinc(br));
    (void)sv_bless(rv, stash);
    DEBUG_wrap(warn("mgwrap %p", ospv); sv_dump(br););
    return rv;}
  case SVt_PVHV:
  case SVt_PVAV:{
    // Leaks XPVRV : unavoidable XXX
    SV *tied;
    if (ospv->get_perl_type() == SVt_PVHV) {
      tied = sv_2mortal((SV*) newHV());		// %tied
    } else {
      tied = sv_2mortal((SV*) newAV());		// @tied
    }
    sv_magic(tied, br, '~', Nullch, 0);		// magic tied, '~', $mgobj
    --SvREFCNT(br);				// like ref_noinc
    SV *rv = newRV_noinc(tied);			// $rv = \tied
    
    if (osp->tie_objects) {
      sv_magic(tied, rv, 'P', Nullch, 0);	// tie tied, CLASS, $rv
      MAGIC *tie_mg = mg_find(tied, 'P');	// undo tie refcnt (yikes!)
      assert(tie_mg);
      tie_mg->mg_flags &= ~(MGf_REFCOUNTED);
      --SvREFCNT(rv);
      //sv_2mortal(rv);
    }
    (void)sv_bless(rv, stash);
    
    DEBUG_wrap(warn("[av]wrap %p", ospv); sv_dump(rv););
    return rv;}
  default:
    osp_croak("osp::ossv_2sv: unknown perl type (%d)", ospv->get_perl_type());
  }
  return 0;
}

SV *osp_thr::ospv_2sv(OSSVPV *pv)
{
  if (!pv) return &sv_undef;
  return wrap(pv, ospv_2bridge(pv));
}

//    if (GIMME_V == G_VOID) return 0;  // fold into ossv_2sv? XXX
// We must to trade speed for paranoia:
SV *osp_thr::ossv_2sv(OSSV *ossv)
{
  if (!ossv) return &sv_undef;
  switch (ossv->natural()) {
  case OSVt_UNDEF:
    return &sv_undef;
  case OSVt_IV32:
    if (!ossv->vptr) return &sv_undef;
    return sv_2mortal(newSViv(OSvIV32(ossv)));
  case OSVt_NV:
    if (!ossv->vptr) return &sv_undef;
    return sv_2mortal(newSVnv(OSvNV(ossv)));
  case OSVt_PV:
    if (!ossv->vptr) return &sv_undef;
    return sv_2mortal(newSVpv((char*) ossv->vptr, ossv->xiv));
  case OSVt_RV:{
    if (!ossv->vptr) return &sv_undef;
    OSSVPV *pv = (OSSVPV*) ossv->vptr;
    return wrap(pv, ospv_2bridge(pv));
  }
  case OSVt_IV16:
    return sv_2mortal(newSViv(OSvIV16(ossv)));
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

OSSV::OSSV() : _type(OSVt_UNDEF)
{}

OSSV::OSSV(SV *nval) : _type(OSVt_UNDEF)
{ this->operator=(nval); }

OSSV::OSSV(OSSV *nval) : _type(OSVt_UNDEF)
{ *this = *nval; }

OSSV::OSSV(OSSVPV *nval) : _type(OSVt_UNDEF)
{ s(nval); }

OSSV::~OSSV()
{
  OSvSHARED_off(this); 
  set_undef();
}

OSSVPV *OSSV::get_ospv()
{
  assert(this);
  if (natural() != OSVt_RV) osp_croak("THIS=%s is not an object", type_2pv());
  assert(vptr);
  return (OSSVPV*)vptr;
}

int OSSV::PvREFok()
{ return natural() == OSVt_RV; }

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

// wacky but assists C++ templates in calling undef
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

  if (SvGMAGICAL(nval))
    mg_get(nval);

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
    osp_croak("OSSV=(SV*): unknown type");
  }
  return this;
}

OSSV *OSSV::operator=(const OSSV &nval)		// i hate const
{ 
  osp_croak("OSSV::operator=(const OSSV &): use memcpy instead"); return 0;
  //  s( (OSSV*) &nval); return this;
}

OSSV *OSSV::operator=(OSSV &nval)
{
  osp_croak("OSSV::operator=(OSSV &): use memcpy instead"); return 0;
  //  s(&nval); return this;
}

int OSSV::operator==(OSSVPV *pv)
{
  if (natural() != OSVt_RV) return 0;
  return vptr == pv;
}

int OSSV::natural() const
{ return OSvTYPE(this); }

int OSSV::is_set()
{ return OSvTYPE(this) != OSVt_UNDEF; }

// prepare to switch to new datatype
int OSSV::morph(int nty)
{
  if (OSvTYPE(this) == nty) return 0;

  if (PvREFok()) PvREF_dec();
  switch (OSvTYPE(this)) {
  case OSVt_UNDEF: break;
  case OSVt_IV32:  delete ((OSPV_iv*)vptr); vptr=0; break;
  case OSVt_NV:    delete ((OSPV_nv*)vptr); vptr=0; break;

  case OSVt_PV:
    DEBUG_assign(warn("OSSV(0x%x)->morph(pv): deleting string '%s' 0x%x",
		      this, vptr, vptr));
    delete [] ((char*)vptr);
    vptr = 0;
    break;

  case OSVt_RV: break;
  case OSVt_IV16: break;

  default: warn("OSSV(0x%p)->morph type %s unknown! (serious error)",
		this, OSSV::type_2pv(OSvTYPE(this)));
  }
  OSvTYPE_set(this, nty);
  return 1;
}

// DANGER! This is ONLY for copying OSSVs between arrays.
void OSSV::FORCEUNDEF()
{ _type = OSVt_UNDEF; }

void OSSV::set_undef()
{
  OSvTRYWRITE(this);
  morph(OSVt_UNDEF);
}

void OSSV::s(os_int32 nval)
{
  OSvTRYWRITE(this);
  if (((os_int16) (nval & 0xffff)) == nval) {
    morph(OSVt_IV16);
    xiv = nval;
    DEBUG_assign(warn("OSSV(0x%x)->s(%d:xi)", this, nval));
  } else {
    if (morph(OSVt_IV32)) {
      vptr = new(os_segment::of(this), OSPV_iv::get_os_typespec()) OSPV_iv;
    }
    OSvIV32(this) = nval;
    DEBUG_assign(warn("OSSV(0x%x)->s(%d:i)", this, nval));
  }
}

void OSSV::s(double nval)
{
  OSvTRYWRITE(this);
  register os_int32 i32_nval = nval;
  if (i32_nval == nval) {
    s(i32_nval);
  } else {
    if (morph(OSVt_NV)) {
      vptr = new(os_segment::of(this), OSPV_nv::get_os_typespec()) OSPV_nv;
    }
    OSvNV(this) = nval;
    DEBUG_assign(warn("OSSV(0x%x)->s(%f:n)", this, nval));
  }
}

// nval must be null terminated or the length must be specified.
// Since the length is not stored, a null terminated is added if not found.
void OSSV::s(char *nval, os_unsigned_int32 nlen)
{
  OSvTRYWRITE(this);
  assert(nlen > 0 || nval[0] == 0);
  if (nlen > 32767) {
    warn("String truncated to 32767 bytes");
    nlen = 32767;
  }
  xiv = nlen;
  if (!morph(OSVt_PV)) {
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

void OSSV::s(OSSVPV *nval)
{ 
  OSvTRYWRITE(this);
  assert(nval);
  STRLEN len;
  DEBUG_assign(warn("OSSV(0x%x)->s(%s=0x%x)", this, nval->os_class(&len), nval));
  if (morph(OSVt_RV)) {
    PvREF_inc(nval);
  } else if (vptr != nval) {
    PvREF_dec();
    PvREF_inc(nval);
  }
}

void OSSV::s(ossv_bridge *br)
{
  if (br->pv) { s(br->pv); return; }
  osp_croak("OSSV::s(ossv_bridge*): assertion failed");
}

void OSSV::s(OSSV *nval)
{ 
  assert(nval);
  switch (nval->natural()) {
  case OSVt_UNDEF: set_undef(); break;
  case OSVt_IV32:  s(OSvIV32(nval)); break;
  case OSVt_NV:    s(OSvNV(nval)); break;
  case OSVt_PV:    s((char*) nval->vptr, nval->xiv); break;
  case OSVt_RV:    s(OSvRV(nval)); break;
  case OSVt_IV16:  s(OSvIV16(nval)); break;
  default:         osp_croak("OSSV::s(OSSV*): assertion failed");
  }
}

char OSSV::strrep[64];
char *OSSV::stringify()
{
  switch (natural()) {
  case OSVt_UNDEF: return "<UNDEF>";
  case OSVt_IV32:  sprintf(strrep, "%ld", OSvIV32(this)); break;
  case OSVt_NV:    sprintf(strrep, "%f", OSvNV(this)); break;
  case OSVt_PV:{
    STRLEN len;
    char *s1 = OSvPV(this, len);
    if (len > 60) len = 60;
    memcpy(strrep, s1, len);
    strrep[len]=0;
    break;}
  case OSVt_RV:    sprintf(strrep, "OBJECT(0x%p)", vptr); break;
  case OSVt_IV16:  sprintf(strrep, "%d", xiv); break;
  default:
    warn("SV %s has no string representation", type_2pv());
    strrep[0]=0;
    break;
  }
  return strrep;
}

int OSSV::istrue()
{
  switch (natural()) {
  case OSVt_UNDEF:  return 0;
  case OSVt_IV32:   return OSvIV32(this) != 0;
  case OSVt_NV:     return OSvNV(this) != 0;
  case OSVt_PV:     return xiv != 0;
  case OSVt_RV:     return 1;
  case OSVt_IV16:   return OSvIV16(this) != 0;
  default:	    osp_croak("unknown type");
  }
}
 
// this  <cmp>  that
//   -1 less than
//        =0=
//  1 greater than

int OSSV::compare(OSSV *that)
{
  int t1 = natural();
  int t2 = that->natural();
  if (t1 == t2) {
    switch (t1) {
    case OSVt_UNDEF: 
      return 0;
    case OSVt_IV32:  
      return OSvIV32(this) - OSvIV32(that);
    case OSVt_NV:
      if (OSvNV(this) == OSvNV(that))
	return 0;
      else if (OSvNV(this) < OSvNV(that))
	return -1;
      else
	return 1;
    case OSVt_PV:{  //adapted from sv_cmp
      STRLEN l1,l2;
      char *pv1 = OSvPV(this, l1);
      char *pv2 = OSvPV(that, l2);
      if (!l1) return l2 ? -1 : 0;
      if (!l2) return 1;
      int retval = memcmp((void*)pv1, (void*)pv2, l1 < l2 ? l1 : l2);
      if (retval) return retval < 0 ? -1 : 1;
      if (l1 == l2)
	return 0;
      else
	return l1 < l2 ? -1 : 1;
    }
    case OSVt_IV16:
      return OSvIV16(this) - OSvIV16(that);
    default:
      osp_croak("OSSV: type '%s' not comparible", type_2pv(t1));
    }
  } else {  //unfortunately, this is a fairly likely case
    if (t1 != OSVt_PV && t2 != OSVt_PV) {
      double v1,v2;
      switch (t1) {
      case OSVt_UNDEF: return -1;
      case OSVt_IV32:  v1 = OSvIV32(this);
      case OSVt_NV:    v1 = OSvNV(this);
      case OSVt_IV16:  v1 = OSvIV16(this);
      default: osp_croak("OSSV: type '%s' not comparible", type_2pv(t1));
      }
      switch (t2) {
      case OSVt_UNDEF: return 1;
      case OSVt_IV32:  v2 = OSvIV32(this);
      case OSVt_NV:    v2 = OSvNV(this);
      case OSVt_IV16:  v2 = OSvIV16(this);
      default: osp_croak("OSSV: type '%s' not comparible", type_2pv(t2));
      }
      if (v1 == v1) return 0;
      if (v1 < v2)
	return -1;
      else 
	return 1;
    } else {
      if (t1 == OSVt_UNDEF) return -1;
      if (t2 == OSVt_UNDEF) return 1;
      if (t1 == OSVt_PV) {
	osp_croak("OSSV: cannot compare a string with %s", type_2pv(t2));
      } else {
	osp_croak("OSSV: cannot compare a string with %s", type_2pv(t1));
      }
    }
  }
}
 
char *OSSV::type_2pv(int ty)
{
  switch (ty) {
   case OSVt_UNDEF:  return "undef";
   case OSVt_IV32:   return "int32";
   case OSVt_NV:     return "double";
   case OSVt_PV:     return "string";
   case OSVt_RV:     return "OBJECT";
   case OSVt_IV16:   return "int16";
   default:
     sprintf(strrep, "ossv(%d)", ty);
     return strrep;
  }
}

char *OSSV::type_2pv()
{
  int ty = natural();
  switch (ty) {
   case OSVt_UNDEF:  return "undef";
   case OSVt_IV32:   return "int32";
   case OSVt_NV:     return "double";
   case OSVt_PV:     return "string";
   case OSVt_RV:
     sprintf(strrep, "OBJECT(0x%p)", vptr);
     return strrep;
   case OSVt_IV16:   return "int16";
   default:
     sprintf(strrep, "ossv(%d)", ty);
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
  if (OSPvBLESS2(this) && classname) ((OSSVPV*)classname)->REF_dec();
}

// C++ API for perl 'bless' (elaborate version)
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
  XPUSHs(sv_mortalcopy(stash));
  PUTBACK;
  perl_call_pv("ObjStore::bless", G_SCALAR);
}

int OSSVPV::_is_blessed()
{ return classname != 0; }

HV *OSSVPV::stash()
{
  STRLEN bslen;
  char *bs = blessed_to(&bslen);
  return gv_stashpvn(bs, bslen, 0);
}

char *OSSVPV::blessed_to(STRLEN *CLEN)
{
  // MUST BE FASTER
  dOSP;
  char *CLASS=0;

  if (classname) {
    if (OSPvBLESS2(this)) {
      OSPV_Generic *av = (OSPV_Generic*)classname;
      assert(av);
      OSSV *str = av->FETCHi(1);
      assert(str && str->natural() == OSVt_PV);
      CLASS = OSvPV(str, *CLEN);
    } else {
      // CLASS must be null terminated!
      CLASS = (char*) classname;
      *CLEN = strlen(CLASS);
    }
  }

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
      SV *sv1, *sv2;
      PUSHs(sv1 = sv_2mortal(newSVpv(oscl, len)));
      PUSHs(sv2 = sv_2mortal(newSVpv(CLASS, *CLEN)));
      PUTBACK;
      int count = perl_call_sv(ldr, G_SCALAR);
      SPAGAIN;
      toclass = POPs;
      if (count != 1) {
	osp_croak("$ObjStore::CLASSLOAD('%s', '%s'): %d != 1 args, $@='%s'", 
	      SvPV(sv1, na), SvPV(sv2, na), count, SvPV(GvSV(errgv), na));
      }
      if (!SvPOK(toclass)) {
	osp_croak("$ObjStore::CLASSLOAD('%s', '%s'): got non-string, $@='%s'", 
	      SvPV(sv1, na), SvPV(sv2, na), SvPV(GvSV(errgv), na));
      }
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
static const os_unsigned_int16 REFCNT16 = 65526;           // 2**16 - 10

void OSSVPV::READONLY_inc()
{
  if (OSPvREADONLY(this) < REFCNT16) {
    ++OSPvREADONLY(this);
  } else {
    OSPvREADONLY(this) = ~0;  //permanent!
  }
}

void OSSVPV::READONLY_dec()
{
  if (OSPvREADONLY(this) == 0) osp_croak("%p->READONLY_dec() to -1", this);
  if (OSPvREADONLY(this) < REFCNT16) {
    --OSPvREADONLY(this);
  }
}

void OSSVPV::REF_inc() {
  _refs++;
  if (_refs > REFCNT32) osp_croak("OSSVPV::REF_inc(): _refs > %ud", REFCNT32);
  DEBUG_refcnt(warn("OSSVPV(0x%x)->REF_inc() to %d", this, _refs));
}

void OSSVPV::REF_dec() { 
  if (_refs == 0) {
    warn("Attempt to free unreferenced object (%p)", this);
    return;
  }
  if (_refs == 1 && classname != 0 && !OSPvINUSE(this)) {
    dOSP;
    // cache last lookup to avoid gv_fetchmethod XXX
    SV *meth=0;
    HV *pkg = stash();
    if (pkg)
      meth = (SV*) gv_fetchmethod(pkg, "NOREFS");
    if (meth) {
      OSPvINUSE_on(this); //protect from race condition
      DEBUG_refcnt(warn("%x->enter NOREFS", this));
      SV *br = ospv_2bridge(this);
      SV *me = osp->wrap(this, br);
      dSP;
      PUSHMARK(SP);
      XPUSHs(me);
      PUTBACK;
      perl_call_sv(meth, G_VOID|G_DISCARD);
      ((ossv_bridge*) SvIV(SvRV(br)))->invalidate(); //must avoid extra ref!
      DEBUG_refcnt(warn("%x->exit NOREFS", this));
      OSPvINUSE_off(this);
    }
  }
  _refs--;
  DEBUG_refcnt(warn("OSSVPV(0x%x)->REF_dec() to %d", this, _refs));
  if (_refs == 0) {
    DEBUG_refcnt(warn("%x: begin delete", this));
    delete this;
    DEBUG_refcnt(warn("%x: finish delete", this));
  }
}

int OSSVPV::get_perl_type()
{ return SVt_PVMG; }

char *OSSVPV::os_class(STRLEN *)
{ osp_croak("OSSVPV(0x%x)->os_class() must be overridden", this); return 0; }
char *OSSVPV::rep_class(STRLEN *)
{ osp_croak("OSSVPV(0x%x)->rep_class() not found", this); return 0; }

// Usually will override, but here's a simple default.
ossv_bridge *OSSVPV::new_bridge()
{ return new ossv_bridge(this); }

OSSV *OSSVPV::traverse(char *keyish)
{ osp_croak("OSSVPV(%p)->traverse", this); return 0; }

void OSSVPV::fwd2rep(char *methname, SV **top, int items)
{
  SV *meth=0;
  STRLEN len;
  char *rep = rep_class(&len);
  HV *pkg = gv_stashpvn(rep, len, 0);
  if (pkg) meth = (SV*) gv_fetchmethod(pkg, methname);
  if (!meth) osp_croak("%s(%p)->%s not found", rep, this, methname);
  dSP;
  //  assert(SP == top); XXX
  PUSHMARK(SP);
  SP += items;
  PUTBACK;
  perl_call_sv(meth, GIMME_V);
}

int OSSVPV::is_array() { return 0; }
int OSSVPV::is_hash() { return 0; }

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
{ STRLEN ign; osp_croak("%s->_count not implemented", os_class(&ign)); return 0; }
OSSVPV *OSPV_Container::new_cursor(os_segment *seg)
{ STRLEN ign; osp_croak("%s->new_cursor not implemented", os_class(&ign)); return 0; }
void OSPV_Container::CLEAR() { osp_croak("OSSVPV(0x%x)->CLEAR",this); }

/*--------------------------------------------- GENERIC */

SV *OSPV_Generic::FIRST(ossv_bridge*) { osp_croak("OSSVPV(0x%x)->FIRST",this); return 0; }
SV *OSPV_Generic::NEXT(ossv_bridge*) { osp_croak("OSSVPV(0x%x)->NEXT",this); return 0; }

// hash
OSSV *OSPV_Generic::FETCHp(char *) { osp_croak("OSSVPV(0x%x)->FETCHp",this); return 0; }
OSSV *OSPV_Generic::STOREp(char *, SV *) { osp_croak("OSSVPV(0x%x)->STOREp",this); return 0; }
void OSPV_Generic::DELETE(char *) { osp_croak("OSSVPV(0x%x)->DELETE",this); }
int OSPV_Generic::EXISTS(char *) { osp_croak("OSSVPV(0x%x)->EXISTS",this); return 0; }

// set (depreciated)
void OSPV_Generic::set_add(SV *) { osp_croak("OSSVPV(0x%x)->add",this); }
int OSPV_Generic::set_contains(SV *) { osp_croak("OSSVPV(0x%x)->contains",this); return 0; }
void OSPV_Generic::set_rm(SV *) { osp_croak("OSSVPV(0x%x)->rm",this); }

// array (preliminary)
OSSV *OSPV_Generic::FETCHi(int) { osp_croak("OSSVPV(0x%x)->FETCHi", this); return 0; }
OSSVPV *OSPV_Generic::FETCHx(int) { osp_croak("OSSVPV(0x%x)->FETCHx", this); return 0; }
OSSV *OSPV_Generic::STOREi(int, SV *) { osp_croak("OSSVPV(0x%x)->STOREi",this); return 0; }
int OSPV_Generic::_LENGTH() {osp_croak("OSSVPV(0x%x)->_LENGTH",this); return 0; }
SV *OSPV_Generic::Pop() {osp_croak("OSSVPV(0x%x)->Pop",this); return 0; }
SV *OSPV_Generic::Unshift() {osp_croak("OSSVPV(0x%x)->Unshift",this); return 0; }
void OSPV_Generic::Push(SV *) {osp_croak("OSSVPV(0x%x)->Push",this); }
void OSPV_Generic::Shift(SV *) {osp_croak("OSSVPV(0x%x)->Shift",this); }
int OSPV_Generic::is_array() { return 1; }
int OSPV_Generic::is_hash() { return 1; }

// INDEX
void OSPV_Generic::add(OSSVPV*)
{osp_croak("OSPV_Generic(%p)->add", this);}
void OSPV_Generic::remove(OSSVPV*)
{osp_croak("OSPV_Generic(%p)->remove", this);}
void OSPV_Generic::configure(SV **top, int items)
{ fwd2rep("configure", top, items); }

OSSV *OSPV_Generic::path_2key(OSSVPV *obj, OSPV_Generic *path)
{
  int len = path->_count();
  assert(len > 0);
  int pi = 0;
  while (1) {
    STRLEN slen;
    OSSV *s1 = path->FETCHi(pi);
    assert(s1->natural() == OSVt_PV);
    char *tr = OSvPV(s1, slen);
    assert(tr[slen-1] == 0);  //null terminated!
    OSSV *at = obj->traverse(tr);
    if (!at || !at->is_set()) osp_croak("Could not traverse field '%s'", tr);
    ++pi;
    if (pi == len) {
      return at;
    } else {
      if (at->natural() != OSVt_RV) 
	osp_croak("Index path attempts to traverse through a scalar at '%s'", tr);
      obj = at->get_ospv();
    }
  }
}

int osp_pathexam::our_field(OSSV *at)
{
  int ok=0;
  for (int sx = 0; sx < sharecnt; sx++) {
    if (shared[sx] == at) { ok=1; break; }
  }
  return ok;
}

// path_2key for all keys & updates readonly flags
osp_pathexam::osp_pathexam(OSPV_Generic *paths, OSSVPV *target, char mode_in)
{
  mode = mode_in;
  assert(mode == 's' || mode == 'u');
  assert(paths->is_array());
  int pathcnt = paths->_count();
  assert(pathcnt >= 0 && pathcnt < INDEX_MAXKEYS);
  keycnt = 0;
  sharecnt = 0;

  for (int kx=0; kx < pathcnt; kx++) {
    pcache[kx] = (OSPV_Generic*) paths->FETCHi(kx)->get_ospv();
    assert(pcache[kx]->is_array());

    OSPV_Generic *path = pcache[kx];
    OSSVPV *obj = target;
    int len = path->_count();
    assert(len > 0);
    int pi = 0;
    while (1) {
      STRLEN slen;
      OSSV *s1 = path->FETCHi(pi);
      assert(s1->natural() == OSVt_PV);
      char *tr = OSvPV(s1, slen);
      assert(tr[slen-1] == 0);  //null terminated!
      OSSV *at = obj->traverse(tr);
      if (!at || !at->is_set()) osp_croak("Could not traverse field '%s'", tr);
      if (pi == 0) {
	// field write lock
	if (mode == 's') {
	  if (OSvSHARED(at) && !our_field(at))
	    osp_croak("Field '%s' is already shared", tr);
	  OSvSHARED_on(at);
	} else {
	  if (!OSvSHARED(at)) {
	    assert(our_field(at));
	  }
	  OSvSHARED_off(at);
	}
	shared[sharecnt++] = at;
      }
      ++pi;
      if (pi == len) {
	if (at->natural() == OSVt_RV)
	  osp_croak("Index path ends at a reference at '%s'", tr);
	keys[keycnt++] = at;
	break;
      } else {
	if (at->natural() != OSVt_RV) 
	  osp_croak("Index path attempts to traverse through a scalar at '%s'", tr);
	obj = at->get_ospv();
	// record write lock
	if (mode == 's') {
	  obj->READONLY_inc();
	} else {
	  obj->READONLY_dec();
	}
      }
    }
  }
  assert(keycnt == pathcnt);
}

void osp_pathexam::abort()
{
  assert(mode == 's');  //otherwise, why bother?
  for (int sx=0; sx < sharecnt; sx++) {
    OSvSHARED_off(shared[sx]);
  }
}

// REFERENCES
OSPV_Ref2::OSPV_Ref2()
{}
char *OSPV_Ref2::os_class(STRLEN *len)
{ *len = 13; return "ObjStore::Ref"; }
os_database *OSPV_Ref2::get_database()
{ osp_croak("OSPV_Ref2::get_database()"); return 0; }
char *OSPV_Ref2::dump()
{ osp_croak("OSPV_Ref::dump()"); return 0; }
OSSVPV *OSPV_Ref2::focus()
{ osp_croak("OSPV_Ref::focus()"); return 0; }
int OSPV_Ref2::deleted()
{ osp_croak("OSPV_Ref2(%p)->deleted(): unsupported on this type of ref", this); return 0; }

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
char *OSPV_Cursor2::os_class(STRLEN *len)
{ *len = 16; return "ObjStore::Cursor"; }
os_database *OSPV_Cursor2::get_database()
{ return os_database::of(this); }
int OSPV_Cursor2::deleted()
{ return 0; }
OSSVPV *OSPV_Cursor2::focus()
{ osp_croak("OSPV_Cursor2(0x%x)->focus", this); return 0; }
void OSPV_Cursor2::moveto(I32)
{ osp_croak("OSPV_Cursor2(0x%x)->moveto", this); }
void OSPV_Cursor2::step(I32)
{ osp_croak("OSPV_Cursor2(0x%x)->step", this); }
void OSPV_Cursor2::keys()
{ osp_croak("OSPV_Cursor2(0x%x)->keys", this); }
void OSPV_Cursor2::at()
{ osp_croak("OSPV_Cursor2(0x%x)->at", this); }
void OSPV_Cursor2::store(SV*)
{ osp_croak("OSPV_Cursor2(0x%x)->store", this); }
int OSPV_Cursor2::seek(SV **, int)
{ osp_croak("OSPV_Cursor2(0x%x)->seek", this); return 0; }
void OSPV_Cursor2::ins(SV*, int)
{ osp_croak("OSPV_Cursor2(0x%x)->ins", this); }
void OSPV_Cursor2::del(SV*, int)
{ osp_croak("OSPV_Cursor2(0x%x)->del", this); }
I32 OSPV_Cursor2::pos()
{ osp_croak("OSPV_Cursor2(0x%x)->pos", this); return -1; }
void OSPV_Cursor2::stats()
{ osp_croak("OSPV_Cursor2(0x%x)->stats", this); }

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

//////////////////////////////////////////////////////////////////////
// DEPRECIATED
OSPV_Cursor::OSPV_Cursor(OSSVPV *_at) : OSPV_Ref(_at)
{}
char *OSPV_Cursor::os_class(STRLEN *len)
{ *len = 29; return "ObjStore::DEPRECIATED::Cursor"; }
void OSPV_Cursor::seek_pole(int)
{ osp_croak("OSPV_Cursor(0x%x)->seek_pole()", this); }
void OSPV_Cursor::at()
{ osp_croak("OSPV_Cursor(0x%x)->at()", this); }
void OSPV_Cursor::next()
{ osp_croak("OSPV_Cursor(0x%x)->next()", this); }

