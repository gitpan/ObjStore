// Switch to -*-c++-*- mode please!
// Copyright © 1997-1998 Joshua Nathaniel Pritikin.  All rights reserved.

#include "osperl.h"
#include <ostore/coll.hh>

/* CCov: off */

#define OR_RETURN_UNDEF(cond) if (!(cond)) return &sv_undef;

/* CCov: fatal OLD_SUPPORT_CODE SERIOUS RETURN_BADNAME */
#define OLD_SUPPORT_CODE
#define SERIOUS warn
#define RETURN_BADNAME(len) *len=3;return "???"

/* CCov: on */

/*--------------------------------------------- typemap services */

os_segment *osp_thr::sv_2segment(SV *sv)
{
  if (sv_isa(sv, "ObjStore::Segment")) return (os_segment*) SvIV((SV*)SvRV(sv));
  croak("sv_2segment only accepts ObjStore::Segment");
}

ospv_bridge *osp_thr::sv_2bridge(SV *ref, int force, os_segment *seg)
{
// Is tied?  Examine tied object, extract ospv_bridge from '~'
// Is OSSV in a PVMG?

  DEBUG_decode(mysv_dump(ref));

  if (!SvROK(ref)) {
    if (SvGMAGICAL(ref))
      mg_get(ref);
    if (!SvROK(ref)) {
      if (force) {
	if (!SvOK(ref)) {
	  mysv_dump(ref);
	  croak("sv_2bridge: Use of uninitialized value");
	}
	mysv_dump(ref);
	croak("sv_2bridge: expecting a reference, got a scalar");
      }
      return 0;
    }
  }
  SV *nval = SvRV(ref);

  ospv_bridge *br = 0;
  do {
    if (SvOBJECT(nval) && (SvTYPE(nval) == SVt_PVHV ||
			   SvTYPE(nval) == SVt_PVAV)) {
      MAGIC *magic = mg_find(nval, '~');
      if (!magic) break;
      SV *mgobj = (SV*) magic->mg_obj;
      if (!SvROK(mgobj)) break;
      br = (ospv_bridge*) SvIV((SV*)SvRV(mgobj));
    } else if (SvROK(nval)) {
      nval = SvRV(nval);
      if (SvOBJECT(nval) && SvTYPE(nval) == SVt_PVMG) {
	br = (ospv_bridge*) SvIV(nval);
      }
    }
  } while (0);

  if (br) {
    // until exceptions are more reliable XXX
    if (br->invalid()) croak("sv_2bridge: persistent data out of scope");
    return br;
  }
  if (!force) return 0;
  if (!seg) {
    mysv_dump(ref);
    croak("sv_2bridge: expecting a persistent object");
  }
  {
    dOSP;
    dSP;
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
  }
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
  HV *stash = ospv->stash(1);
  switch (ospv->get_perl_type()) {
  case SVt_PVMG:{
    SV *rv = sv_2mortal(newRV_noinc(br));
    (void)sv_bless(rv, stash);
    DEBUG_wrap(warn("mgwrap %p", ospv); mysv_dump(br););
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
    
    sv_magic(tied, rv, 'P', Nullch, 0);	// tie tied, CLASS, $rv
    MAGIC *tie_mg = mg_find(tied, 'P');	// undo tie refcnt (yikes!)
    assert(tie_mg);
    tie_mg->mg_flags &= ~(MGf_REFCOUNTED);
    --SvREFCNT(rv);
    //sv_2mortal(rv);

    (void)sv_bless(rv, stash);
    
    DEBUG_wrap(warn("[av]wrap %p", ospv); mysv_dump(rv););
    return rv;}
  }
  croak("osp::ossv_2sv: unknown perl type (%d)", ospv->get_perl_type());
  return 0;
}

SV *osp_thr::ospv_2sv(OSSVPV *pv)
{
  OR_RETURN_UNDEF(pv);
  return wrap(pv, ospv_2bridge(pv));
}

//    if (GIMME_V == G_VOID) return 0;  // fold into ossv_2sv? XXX
SV *osp_thr::ossv_2sv(OSSV *ossv)
{
  SV *ret;
  // We must to trade speed for paranoia --
  if (!ossv) return &sv_undef;
  switch (ossv->natural()) {
  case OSVt_UNDEF:
    return &sv_undef;
  case OSVt_IV32:
    OR_RETURN_UNDEF(ossv->vptr);
    ret = sv_2mortal(newSViv(OSvIV32(ossv)));
    break;
  case OSVt_NV:
    OR_RETURN_UNDEF(ossv->vptr);
    ret = sv_2mortal(newSVnv(OSvNV(ossv)));
    break;
  case OSVt_PV:
    if (!ossv->vptr) ret = sv_2mortal(newSVpv("", 0)); //use immortal XXX
    else {
      // Problems with eliding the copy:
      // 1. What if the persistent copy is deleted?  Read transactions only.
      // 2. They can not be packaged as simple SVPV because of the need
      //    to invalidate them.
      // 3. There is significant bookkeeping overhead to invalidate
      //    at the end of the transaction.  Maybe for long strings
      //    only after the regex engine can support it?
      ret = sv_2mortal(newSVpv((char*) ossv->vptr, ossv->xiv));
    }
    break;
  case OSVt_RV:{
    OR_RETURN_UNDEF(ossv->vptr);
    OSSVPV *pv = (OSSVPV*) ossv->vptr;
    ret = wrap(pv, ospv_2bridge(pv));
    break;
  }
  case OSVt_IV16:
    ret = sv_2mortal(newSViv(OSvIV16(ossv)));
    break;
  default:
    SERIOUS("OSSV %s is not implemented", ossv->type_2pv());
    return &sv_undef;
  }
  assert(ret);
  if (OSvREADONLY(ossv)) SvREADONLY_on(ret);
  return ret;
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
  assert(nval);
  assert(seg);
  if (SvROK(nval)) {
    ospv_bridge *br = osp->sv_2bridge(nval, 1, seg);
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

OSSV::OSSV(OSSVPV *nval) : _type(OSVt_UNDEF)
{ s(nval); }

OSSV::~OSSV()
{
  OSvROCLEAR(this);
  set_undef();
}

/*
OSPV_Generic *OSSV::ary()
{
  assert(this);
  assert(natural() == OSVt_RV);
  assert(vptr);
  return (OSPV_Generic*)vptr;
}
*/

OSSVPV *OSSV::get_ospv()
{
  assert(this);
  if (natural() != OSVt_RV) croak("THIS=%s is not an object", type_2pv());
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
  char *tmp; STRLEN tmplen;

  DEBUG_decode(mysv_dump(nval));

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
  } else if (SvPOK(nval) || SvPOKp(nval)) {
    tmp = SvPV(nval, tmplen);
    s(tmp, tmplen);
  } else if (! SvOK(nval)) {
    set_undef();
  } else {
    mysv_dump(nval);
    croak("OSSV=(SV*): unknown type");
  }
  return this;
}

// Must preserve flags (like shared) that can easily become unset!
OSSV *OSSV::operator=(const OSSV &nval)
{ croak("OSSV::operator=(const OSSV &): use memcpy/memmove instead"); return 0; }
OSSV *OSSV::operator=(OSSV &nval)
{ croak("OSSV::operator=(OSSV &): use memcpy/memmove instead"); return 0; }

// DANGER! This is ONLY to assist in memcpy'ing OSSVs between arrays.
void OSSV::FORCEUNDEF()
{ _type = OSVt_UNDEF; vptr=0; }  //vptr=0 seems to be necessary

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
    if (vptr) {
      DEBUG_assign(warn("OSSV(0x%x)->morph(pv): deleting string '%s' 0x%x",
			this, vptr, vptr));
      delete [] ((char*)vptr);
      vptr = 0;
    }
    break;

  case OSVt_RV: 
    assert(vptr==0);
    break;
  case OSVt_IV16: break;

  default: croak("OSSV(0x%p)->morph type %s unknown! (serious error)",
		 this, OSSV::type_2pv(OSvTYPE(this)));
  }
  OSvTYPE_set(this, nty);
  return 1;
}

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

void OSSV::s(char *nval, os_unsigned_int32 nlen)
{
  // Go through extra contortions for speed...
  OSvTRYWRITE(this);
  if (nlen == 0) {
    morph(OSVt_PV);
    if (vptr) {
      DEBUG_assign(warn("OSSV(0x%x)->s(): deleting string 0x%x", this, vptr));
      delete [] ((char*)vptr);
      vptr = 0;
    }
    xiv = 0;
    return;
  }
  if (nlen > 32760) {
    warn("ObjStore: string of length %d truncated to 32760 bytes", nlen);
    nlen = 32760;
  }
  int LONGISH = nlen > 16 ? 1 : 0;
  if (!morph(OSVt_PV)) {
    if (xiv == nlen) {
      //already ok
      assert(vptr);
      //    } else if (xiv > nlen && xiv - nlen <= 8) {
      //      ((char*)vptr)[nlen] = 0;
    } else {
      if (vptr) {
	DEBUG_assign(warn("OSSV(0x%x)->s(): deleting string 0x%x", this, vptr));
	delete [] ((char*)vptr);
      }
      vptr = new(os_segment::of(this), os_typespec::get_char(),
		 nlen+LONGISH) char[nlen+LONGISH];
      if (LONGISH) ((char*)vptr)[nlen] = 0;
    }
  } else {
    vptr = new(os_segment::of(this), os_typespec::get_char(),
	       nlen+LONGISH) char[nlen+LONGISH];
    if (LONGISH) ((char*)vptr)[nlen] = 0;
  }
  memcpy(vptr, nval, nlen);
  xiv = nlen;
  DEBUG_assign(warn("OSSV(0x%x)->s(%s, %d): 0x%x", this, nval, nlen, vptr));
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

void OSSV::s(ospv_bridge *br)
{
  if (br->pv) { s(br->pv); return; }
  croak("OSSV::s(ospv_bridge*): assertion failed");
}

/*
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
  default:         croak("OSSV::s(OSSV*): assertion failed");
  }
}
*/

/* CCov: off */
char OSSV::strrep1[64];
char *OSSV::stringify() // debugging ONLY!
{
  switch (natural()) {
  case OSVt_UNDEF: return "<UNDEF>";
  case OSVt_IV32:  sprintf(strrep1, "%ld", OSvIV32(this)); break;
  case OSVt_NV:    sprintf(strrep1, "%f", OSvNV(this)); break;
  case OSVt_PV:{
    STRLEN len;
    char *s1 = OSvPV(this, len);
    if (len > 60) len = 60;
    if (len) {assert(s1); memcpy(strrep1, s1, len);}
    strrep1[len]=0;
    break;}
  case OSVt_RV:    sprintf(strrep1, "OBJECT(0x%p)", vptr); break;
  case OSVt_IV16:  sprintf(strrep1, "%d", xiv); break;
  default:
    warn("SV %s has no string representation", type_2pv());
    strrep1[0]=0;
    break;
  }
  return strrep1;
}
/* CCov: on */

int OSSV::istrue()
{
  switch (natural()) {
  case OSVt_UNDEF:  return 0;
  case OSVt_IV32:   return OSvIV32(this) != 0;
  case OSVt_NV:     return OSvNV(this) != 0;
  case OSVt_PV:     return xiv != 0;
    //  case OSVt_RV:     return 1;
  case OSVt_IV16:   return OSvIV16(this) != 0;
  default:	    SERIOUS("istrue: unknown type"); return 0;
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
      croak("OSSV: type '%s' not comparible", type_2pv(t1));
    }
  } else {  //unfortunately, this is a fairly likely case
    if (t1 != OSVt_PV && t2 != OSVt_PV) {
      double v1,v2;
      switch (t1) {
      case OSVt_UNDEF: return -1;
      case OSVt_IV32:  v1 = OSvIV32(this); break;
      case OSVt_NV:    v1 = OSvNV(this); break;
      case OSVt_IV16:  v1 = OSvIV16(this); break;
      default: croak("OSSV: %s not numerically comparible", type_2pv(t1));
      }
      switch (t2) {
      case OSVt_UNDEF: return 1;
      case OSVt_IV32:  v2 = OSvIV32(that); break;
      case OSVt_NV:    v2 = OSvNV(that); break;
      case OSVt_IV16:  v2 = OSvIV16(that); break;
      default: croak("OSSV: %s not numerically comparible", type_2pv(t2));
      }
      assert(v1 != v2); //type mixup should be impossible
      if (v1 < v2)
	return -1;
      else 
	return 1;
    } else {
      if (t1 == OSVt_UNDEF) { return -1; }
      else if (t2 == OSVt_UNDEF) { return 1; }
      else if (t1 == OSVt_PV) {
	croak("OSSV: cannot compare a string with %s", type_2pv(t2));
      } else {
	croak("OSSV: cannot compare a string with %s", type_2pv(t1));
      }
    }
  }
}

/* CCov: off */

void OSSV::verify_correct_compare()
{
  OSSV o1,o2;

  assert(o1.compare(&o2) == 0);
  assert(o1.istrue() == 0);
  o1.s(4);
  assert(o1.istrue());
  o1.s(40000);
  assert(o1.istrue());
  o1.s(1.5);
  assert(o1.istrue());
  o1.s("test", 4);
  assert(o1.istrue());

  o1.set_undef();
  o2.s("test", 4);
  assert(o1.compare(&o2) < 0);
  assert(o2.compare(&o1) > 0);
  o2.s(1.5);
  assert(o1.compare(&o2) < 0);
  assert(o2.compare(&o1) > 0);

  o1.s(.5);
  o2.s(.5);
  assert(o1.compare(&o2) == 0);
  o2.s(1.5);
  assert(o1.compare(&o2) < 0 && o2.compare(&o1) > 0);

  o1.s(1);
  o2.s(2);
  assert(o1.compare(&o2) < 0 && o2.compare(&o1) > 0);
  o2.s(40000);
  assert(o1.compare(&o2) < 0 && o2.compare(&o1) > 0);
  o2.s(1.5);
  assert(o1.compare(&o2) < 0 && o2.compare(&o1) > 0);

  o1.s(40000);
  o2.s(50000);
  assert(o1.compare(&o2) < 0 && o2.compare(&o1) > 0);

  o1.s("", 0);
  o2.s("", 0);
  assert(o1.compare(&o2) == 0);
  o2.s("test", 4);
  assert(o1.compare(&o2) < 0 && o2.compare(&o1) > 0);
  o1.s("abc", 3);
  assert(o1.compare(&o2) < 0 && o2.compare(&o1) > 0);
  o1.s("abcd", 4);
  assert(o1.compare(&o2) < 0 && o2.compare(&o1) > 0);
  o1.s("test", 4);
  assert(o1.compare(&o2) == 0);
  o2.s("test2", 5);
  assert(o1.compare(&o2) < 0 && o2.compare(&o1) > 0);
  
  // there's nothing like 100% ...
}

char OSSV::strrep2[64];
char *OSSV::type_2pv(int ty)  //debugging ONLY
{
  switch (ty) {
   case OSVt_UNDEF:  return "undef";
   case OSVt_IV32:   return "int32";
   case OSVt_NV:     return "double";
   case OSVt_PV:     return "string";
   case OSVt_RV:     return "OBJECT";
   case OSVt_IV16:   return "int16";
   default:
     sprintf(strrep2, "ossv(%d)", ty);
     return strrep2;
  }
}

char *OSSV::type_2pv()  //debugging ONLY
{
  int ty = natural();
  switch (ty) {
   case OSVt_UNDEF:  return "undef";
   case OSVt_IV32:   return "int32";
   case OSVt_NV:     return "double";
   case OSVt_PV:     return "string";
   case OSVt_RV:
     sprintf(strrep2, "OBJECT(0x%p)", vptr);
     return strrep2;
   case OSVt_IV16:   return "int16";
   default:
     sprintf(strrep2, "ossv(%d)", ty);
     return strrep2;
  }
}
/* CCov: on */

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
  if (cur1 == cur2 && memcmp((void*)pv1, (void*)pv2, cur1) == 0) {
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

HV *OSSVPV::stash(int create)
{
  STRLEN bslen;
  char *bs = blessed_to(&bslen);
  return gv_stashpvn(bs, bslen, create);
}

char *OSSVPV::blessed_to(STRLEN *CLEN)
{
  // MUST BE FASTER!!
  dOSP;
  char *CLASS=0;

  if (classname) {
    if (OSPvBLESS2(this)) {
      OSPV_Generic *av = (OSPV_Generic*)classname;
      assert(av);
      OSSV *str = av->avx(1);
      assert(str && str->natural() == OSVt_PV);
      CLASS = OSvPV(str, *CLEN);
    } else {
      // CLASS must be null terminated!
      CLASS = (char*) classname;
      *CLEN = strlen(CLASS);
      OLD_SUPPORT_CODE
    }
  }

  if (CLASS) {
    // roll up into database open? XXX
    SV *toclass=0;
    SV **msvp = hv_fetch(osp->CLASSLOAD, CLASS, *CLEN, 0); //in CACHE?
    if (msvp) toclass = *msvp;

    if (!toclass || !SvPOK(toclass)) {		// load and add to CACHE
      // CAN BE SLOW
      STRLEN len;
      char *oscl = os_class(&len);
      if (len != strlen(oscl)) croak("os_class(): length of %s is wrong", oscl);
      SV *ldr = perl_get_sv("ObjStore::CLASSLOAD", 0);
      assert(ldr);
      dSP;
      ENTER;
      SAVETMPS;
      PUSHMARK(SP);
      EXTEND(SP, 3);
      PUSHs(sv_2mortal(newSVpv("the database is not relavent", 0)));
      SV *sv1, *sv2;
      assert(len);
      PUSHs(sv1 = sv_2mortal(newSVpv(oscl, len)));
      assert(CLEN && *CLEN);
      PUSHs(sv2 = sv_2mortal(newSVpv(CLASS, *CLEN)));
      PUTBACK;
      int count = perl_call_sv(ldr, G_SCALAR);
      SPAGAIN;
      toclass = POPs;
      if (count != 1) {
	croak("$ObjStore::CLASSLOAD('%s', '%s'): %d != 1 args, $@='%s'", 
	      SvPV(sv1, na), SvPV(sv2, na), count, SvPV(GvSV(errgv), na));
      }
      if (!SvPOK(toclass)) {
	croak("$ObjStore::CLASSLOAD('%s', '%s'): got non-string, $@='%s'", 
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

void OSSVPV::ROCNT_inc()
{
  if (OSPvROCNT(this) < REFCNT16) {
    ++OSPvROCNT(this);
  } else {
    OSPvROCNT(this) = ~0;  //permanent!
  }
}

void OSSVPV::ROCNT_dec()
{
  if (OSPvROCNT(this) < REFCNT16) {
    if (OSPvROCNT(this) <= 1) {
      assert(OSPvROCNT(this) == 1);
      ROSHARE_set(0);
    }
    --OSPvROCNT(this);
  }
}

void OSSVPV::REF_inc() {
  DEBUG_refcnt(warn("OSSVPV(0x%x)->REF_inc() from %d", this, _refs));
  _refs++;
  if (_refs > REFCNT32) croak("OSSVPV::REF_inc(): _refs > %ud", REFCNT32);
}

void OSSVPV::REF_dec() { 
  if (_refs == 0) {
    SERIOUS("ObjStore: attempt to free unreferenced object (%p)", this);
    return;
  }
  if (_refs == 1 && classname != 0 && !OSPvINUSE(this)) {
    dOSP;
    // cache last lookup to avoid gv_fetchmethod? XXX
    SV *meth=0;
    HV *pkg = stash(0);
    if (pkg)
      meth = (SV*) gv_fetchmethod(pkg, "NOREFS");
    if (meth) {
      OSPvINUSE_on(this); //protect from race condition
      DEBUG_norefs(warn("%x->enter NOREFS", this));
      SV *br = ospv_2bridge(this);
      SV *me = osp->wrap(this, br);
      dSP;
      ENTER;
      PUSHMARK(SP);
      XPUSHs(me);
      PUTBACK;
      perl_call_sv((SV*)GvCV(meth), G_DISCARD|G_EVAL|G_KEEPERR);
      ((osp_bridge*) SvIV(SvRV(br)))->invalidate(); //must avoid extra ref!
      LEAVE;
      DEBUG_norefs(warn("%x->exit NOREFS", this));
      OSPvINUSE_off(this);
    } else {
      DEBUG_norefs(warn("%x->NOREFS not found", this));
    }
    // Probably should support the exact same re-bless symantics
    // that DESTROY supports. XXX
  }
  _refs--;
  DEBUG_refcnt(warn("OSSVPV(0x%x)->REF_dec() to %d", this, _refs));
  if (_refs == 0) {
    DEBUG_norefs(warn("OSSVPV(0x%x): begin delete", this));
    delete this;
    DEBUG_norefs(warn("OSSVPV(0x%x): finish delete", this));
  }
}

int OSSVPV::get_perl_type()
{ return SVt_PVMG; }

int OSSVPV::can_update(void *vptr)
{
  if (os_segment::of(this) == os_segment::of(0)) {
    // might be updating the transient index in read mode
    dOSP; dTXN;
    return txn->can_update(vptr);
  } else {
    // can only be in update mode
    return 1;
  }
}

/* CCov: fatal NOTFOUND */
void OSSVPV::NOTFOUND(char *meth)
{
  STRLEN len;
  croak("OSSVPV(%p) '%s' method unsupported (os_class='%s' rep_class='%s')",
	this, meth, os_class(&len), rep_class(&len));
}

char *OSSVPV::os_class(STRLEN *len)
{ RETURN_BADNAME(len); }
char *OSSVPV::rep_class(STRLEN *len)
{ RETURN_BADNAME(len); }

// Usually will override, but here's a simple default.
ospv_bridge *OSSVPV::new_bridge()
{ return new ospv_bridge(this); }

OSSV *OSSVPV::traverse(char *keyish)
{ NOTFOUND("traverse"); return 0; }
OSSVPV *OSSVPV::traverse2(char *keyish)
{ return 0; }
void OSSVPV::ROSHARE_set(int)
{ NOTFOUND("ROSHARE_set"); }

void OSSVPV::fwd2rep(char *methname, SV **top, int items)
{
  SV *meth=0;
  STRLEN len;
  char *rep = rep_class(&len);
  HV *pkg = gv_stashpvn(rep, len, 0);
  if (pkg) meth = (SV*) gv_fetchmethod(pkg, methname);
  if (!meth) NOTFOUND(methname);
  dSP;
  //  assert(SP == top); XXX
  PUSHMARK(SP);
  SP += items;
  PUTBACK;
  perl_call_sv(meth, GIMME_V);
}

/*--------------------------------------------- ospv_bridge */

ospv_bridge::ospv_bridge(OSSVPV *_pv)
  : pv(_pv)
{
  is_transient = os_segment::of(pv) == os_segment::of(0);
  can_delete = 0;
  BrDEBUG_set(this, 0);

  dOSP; dTXN;
  assert(pv);
  STRLEN junk;
  DEBUG_bridge(this,warn("ospv_bridge 0x%x->new(%s=0x%x) is_transient=%d",
		    this, _pv->os_class(&junk), pv, is_transient));
  if (txn->can_update(pv) || is_transient) pv->REF_inc();
}

ospv_bridge::~ospv_bridge()
{
  //  assert(ready());
  if (!ready()) 
    croak("persistent data being used outside of it's transaction");
}
OSSVPV *ospv_bridge::ospv()
{ assert(pv); return pv; }
int ospv_bridge::ready()
{ return can_delete && !pv; }
void ospv_bridge::release()
{ unref(); can_delete = 1; }
int ospv_bridge::invalid()
{ return pv==0; }
void ospv_bridge::invalidate()
{
  // If transient, has lifetime outside of a transaction.  Let perl
  // decide when to delete it.
  if (is_transient) return;
  unref();
}

void ospv_bridge::unref()
{
  if (!pv) return;
  OSSVPV *copy = pv;  //avoid any potential race condition
  pv=0;

  dOSP ; dTXN ;
  assert(txn);
  DEBUG_bridge(this, warn("ospv_bridge 0x%x->unref(pv=0x%x) updt=%d",
		    this, copy, txn->can_update(copy)));
  assert(copy);
  if (txn->can_update(copy)) {
    copy->REF_dec();
  }
}

/*--------------------------------------------- INTERFACES */

double OSPV_Container::_percent_filled()
{ NOTFOUND("_percent_filled"); return -1; }
int OSPV_Container::FETCHSIZE()
{ NOTFOUND("FETCHSIZE"); return 0; }
OSSVPV *OSPV_Container::new_cursor(os_segment *seg)
{ NOTFOUND("new_cursor"); return 0; }
void OSPV_Container::CLEAR() { NOTFOUND("CLEAR"); }

/*--------------------------------------------- GENERIC */

SV *OSPV_Generic::FIRST(ospv_bridge*) { NOTFOUND("FIRST"); return 0; }
SV *OSPV_Generic::NEXT(ospv_bridge*) { NOTFOUND("NEXT"); return 0; }

// hash
OSSV *OSPV_Generic::hvx(char *) { NOTFOUND("hvx"); return 0; }
OSSV *OSPV_Generic::FETCH(SV *) { NOTFOUND("FETCH"); return 0; }
OSSV *OSPV_Generic::STORE(SV *, SV *) { NOTFOUND("STORE"); return 0; }
void OSPV_Generic::DELETE(char *) { NOTFOUND("DELETE"); }
int OSPV_Generic::EXISTS(char *) { NOTFOUND("EXISTS"); return 0; }

// array
OSSV *OSPV_Generic::avx(int) { NOTFOUND("avx"); return 0; }
SV *OSPV_Generic::POP() { NOTFOUND("POP"); return 0; }
SV *OSPV_Generic::SHIFT() { NOTFOUND("SHIFT"); return 0; }
void OSPV_Generic::PUSH(SV **,int) { NOTFOUND("PUSH"); }
void OSPV_Generic::UNSHIFT(SV **,int) { NOTFOUND("UNSHIFT"); }
void OSPV_Generic::SPLICE(int, int, SV **, int) { NOTFOUND("SPLICE"); }

// INDEX
OSSVPV *OSPV_Generic::FETCHx(SV*) { NOTFOUND("FETCHx"); return 0; }
void OSPV_Generic::add(OSSVPV*) { NOTFOUND("add"); }
void OSPV_Generic::remove(OSSVPV*) { NOTFOUND("remove"); }
void OSPV_Generic::configure(SV **top, int items)
{ fwd2rep("configure", top, items); }

OSSV *OSPV_Generic::path_2key(OSSVPV *obj, OSPV_Generic *path)
{
  int len = path->FETCHSIZE();
  assert(len > 0);
  int pi = 0;
  while (1) {
    STRLEN slen;
    OSSV *s1 = path->avx(pi);
    assert(s1->natural() == OSVt_PV);
    char *tr = OSvPV(s1, slen);
    assert(tr && tr[slen-1] == 0);  //null terminated!
    OSSV *at = obj->traverse(tr);
    if (!at || !at->is_set()) {
      croak("Could not traverse field '%s'", tr);
      //return 0;
    }
    ++pi;
    if (pi == len) {
      return at;
    } else {
      if (at->natural() != OSVt_RV) 
	croak("Index path attempts to traverse through a scalar at '%s'", tr);
      obj = at->get_ospv();
    }
  }
}

// symantics are a little bizarre; ideas for improvement welcome
void osp_pathexam::abort()
{
  assert(mode == 's');
  if (!is_excl) {
    for (int xx=0; xx < trailcnt; xx++) {
      trail[xx]->ROCNT_dec();
    }
  }
}

void osp_pathexam::commit()
{
  if (!is_excl && mode == 'u') {
    for (int xx=0; xx < trailcnt; xx++) {
      trail[xx]->ROCNT_dec();
    }
  } else if (is_excl && mode == 's') {
    if (!excl_ok) 
      croak("attempt to exclusive-index key twice"); //better diagnostics XXX
  }
}

// path_2key for all keys & updates readonly flags
osp_pathexam::osp_pathexam(OSPV_Generic *paths, OSSVPV *target, char mode_in,
			   int exclusive)
{
  excl_ok = 1;
  is_excl = exclusive;
  int flag = is_excl? OSVf_ROEXCL : OSVf_ROSHARE;
  failed=0;
  mode = mode_in;
  assert(mode == 's' || mode == 'u');

  int pathcnt = paths->FETCHSIZE();
  if (pathcnt < 1) croak("Index path unset");
  assert(pathcnt < INDEX_MAXKEYS);

  keycnt = 0;
  trailcnt = 0;

  for (int kx=0; kx < pathcnt; kx++) {
    pcache[kx] = (OSPV_Generic*) paths->avx(kx)->get_ospv();

    OSPV_Generic *path = pcache[kx];
    int len = path->FETCHSIZE();
    assert(len > 0);

    int pstep = 0;
    OSSVPV *obj = target;

    while (1) {
      OSSV *s1 = path->avx(pstep);
      assert(s1->natural() == OSVt_PV);

      STRLEN slen;
      char *tr = OSvPV(s1, slen);
      assert(tr && tr[slen-1] == 0);  //verify null terminated

      if (mode == 's' && !is_excl) obj->ROCNT_inc();
      trail[trailcnt++] = obj;

      OSSV *at = obj->traverse(tr);
      if (!at || !at->is_set()) {
	//croak("Could not traverse field '%s'", tr);
	failed=1;
	if (mode == 's') abort();
	return;
      }

      if (mode == 's') {
	if (is_excl && OSvROEXCL(at)) {
	  excl_ok = 0;
	}
	OSvFLAG_set(at, flag, 1);
      } else {
	if (is_excl) OSvFLAG_set(at, flag, 0);
      }

      if (++pstep < len) {
	if (at->natural() != OSVt_RV) 
	  croak("Index path attempts to traverse through a scalar at '%s'", tr);
	obj = at->get_ospv();

      } else {
	if (at->natural() == OSVt_RV)
	  croak("Index path ends at a reference at '%s'", tr);
	keys[keycnt++] = at;
	break;
      }
    }
  }
  assert(keycnt == pathcnt);
}

// SET (DEPRECIATED)
void OSPV_Generic::set_add(SV *) { NOTFOUND("add"); }
int OSPV_Generic::set_contains(SV *) { NOTFOUND("contains"); return 0; }
void OSPV_Generic::set_rm(SV *) { NOTFOUND("rm"); }

// REFERENCES
OSPV_Ref2::OSPV_Ref2()
{}
char *OSPV_Ref2::os_class(STRLEN *len)
{ *len = 13; return "ObjStore::Ref"; }
os_database *OSPV_Ref2::get_database() { NOTFOUND("get_database"); return 0; }
char *OSPV_Ref2::dump() { NOTFOUND("dump"); return 0; }
OSSVPV *OSPV_Ref2::focus() { NOTFOUND("focus"); return 0; }
int OSPV_Ref2::deleted() { NOTFOUND("deleted"); return 0; }

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
char *OSPV_Cursor2::rep_class(STRLEN *len)
{ return focus()->rep_class(len); }

//override like REFS if cross-database allowed
/*
os_database *OSPV_Cursor2::get_database()
{ return os_database::of(this); }
int OSPV_Cursor2::deleted()
{ return 0; }
*/
//cross-database

OSSVPV *OSPV_Cursor2::focus() { NOTFOUND("focus"); return 0; }
void OSPV_Cursor2::moveto(I32){ NOTFOUND("moveto"); }
void OSPV_Cursor2::step(I32) { NOTFOUND("step"); }
void OSPV_Cursor2::keys() { NOTFOUND("keys"); }
void OSPV_Cursor2::at() { NOTFOUND("at"); }
void OSPV_Cursor2::store(SV*) { NOTFOUND("store"); }
int OSPV_Cursor2::seek(SV **, int) { NOTFOUND("seek"); return 0; }
void OSPV_Cursor2::ins(SV*, int) { NOTFOUND("ins"); }
void OSPV_Cursor2::del(SV*, int) { NOTFOUND("del"); }
I32 OSPV_Cursor2::pos() { NOTFOUND("pos"); return -1; }
void OSPV_Cursor2::stats() { NOTFOUND("stats"); }

//////////////////////////////////////////////////////////////////////
// DEPRECIATED
/* CCov: off */
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
{ NOTFOUND("seek_pole"); }
void OSPV_Cursor::at()
{ NOTFOUND("at"); }
void OSPV_Cursor::next()
{ NOTFOUND("next"); }

//////////////////////////////////////////////////////////////////////
// adapted from perl 5.004_63

#ifndef Perl_debug_log
#define Perl_debug_log	PerlIO_stderr()
#endif
extern "C" void mysv_dump(SV *sv)
{
    SV *d = sv_newmortal();
    char *s;
    U32 flags;
    U32 type;

    if (!sv) {
	PerlIO_printf(Perl_debug_log, "SV = 0\n");
	return;
    }
    
    flags = SvFLAGS(sv);
    type = SvTYPE(sv);

    sv_setpvf(d, "(0x%lx)\n  REFCNT = %ld\n  FLAGS = (",
	      (unsigned long)SvANY(sv), (long)SvREFCNT(sv));
    if (flags & SVs_PADBUSY)	sv_catpv(d, "PADBUSY,");
    if (flags & SVs_PADTMP)	sv_catpv(d, "PADTMP,");
    if (flags & SVs_PADMY)	sv_catpv(d, "PADMY,");
    if (flags & SVs_TEMP)	sv_catpv(d, "TEMP,");
    if (flags & SVs_OBJECT)	sv_catpv(d, "OBJECT,");
    if (flags & SVs_GMG)	sv_catpv(d, "GMG,");
    if (flags & SVs_SMG)	sv_catpv(d, "SMG,");
    if (flags & SVs_RMG)	sv_catpv(d, "RMG,");

    if (flags & SVf_IOK)	sv_catpv(d, "IOK,");
    if (flags & SVf_NOK)	sv_catpv(d, "NOK,");
    if (flags & SVf_POK)	sv_catpv(d, "POK,");
    if (flags & SVf_ROK)	sv_catpv(d, "ROK,");
    if (flags & SVf_OOK)	sv_catpv(d, "OOK,");
    if (flags & SVf_FAKE)	sv_catpv(d, "FAKE,");
    if (flags & SVf_READONLY)	sv_catpv(d, "READONLY,");

#ifdef OVERLOAD
    if (flags & SVf_AMAGIC)	sv_catpv(d, "OVERLOAD,");
#endif /* OVERLOAD */
    if (flags & SVp_IOK)	sv_catpv(d, "pIOK,");
    if (flags & SVp_NOK)	sv_catpv(d, "pNOK,");
    if (flags & SVp_POK)	sv_catpv(d, "pPOK,");
    if (flags & SVp_SCREAM)	sv_catpv(d, "SCREAM,");

    switch (type) {
    case SVt_PVCV:
    case SVt_PVFM:
	if (CvANON(sv))		sv_catpv(d, "ANON,");
	if (CvUNIQUE(sv))	sv_catpv(d, "UNIQUE,");
	if (CvCLONE(sv))	sv_catpv(d, "CLONE,");
	if (CvCLONED(sv))	sv_catpv(d, "CLONED,");
	if (CvNODEBUG(sv))	sv_catpv(d, "NODEBUG,");
	break;
    case SVt_PVHV:
	if (HvSHAREKEYS(sv))	sv_catpv(d, "SHAREKEYS,");
	if (HvLAZYDEL(sv))	sv_catpv(d, "LAZYDEL,");
	break;
    case SVt_PVGV:
	if (GvINTRO(sv))	sv_catpv(d, "INTRO,");
	if (GvMULTI(sv))	sv_catpv(d, "MULTI,");
	if (GvASSUMECV(sv))	sv_catpv(d, "ASSUMECV,");
	if (GvIMPORTED(sv)) {
	    sv_catpv(d, "IMPORT");
	    if (GvIMPORTED(sv) == GVf_IMPORTED)
		sv_catpv(d, "ALL,");
	    else {
		sv_catpv(d, "(");
		if (GvIMPORTED_SV(sv))	sv_catpv(d, " SV");
		if (GvIMPORTED_AV(sv))	sv_catpv(d, " AV");
		if (GvIMPORTED_HV(sv))	sv_catpv(d, " HV");
		if (GvIMPORTED_CV(sv))	sv_catpv(d, " CV");
		sv_catpv(d, " ),");
	    }
	}
    case SVt_PVBM:
	if (SvTAIL(sv))	sv_catpv(d, "TAIL,");
	if (SvCOMPILED(sv))	sv_catpv(d, "COMPILED,");
	break;
    }

    if (*(SvEND(d) - 1) == ',')
	SvPVX(d)[--SvCUR(d)] = '\0';
    sv_catpv(d, ")");
    s = SvPVX(d);

    PerlIO_printf(Perl_debug_log, "SV = ");
    switch (type) {
    case SVt_NULL:
	PerlIO_printf(Perl_debug_log, "NULL%s\n", s);
	return;
    case SVt_IV:
	PerlIO_printf(Perl_debug_log, "IV%s\n", s);
	break;
    case SVt_NV:
	PerlIO_printf(Perl_debug_log, "NV%s\n", s);
	break;
    case SVt_RV:
	PerlIO_printf(Perl_debug_log, "RV%s\n", s);
	break;
    case SVt_PV:
	PerlIO_printf(Perl_debug_log, "PV%s\n", s);
	break;
    case SVt_PVIV:
	PerlIO_printf(Perl_debug_log, "PVIV%s\n", s);
	break;
    case SVt_PVNV:
	PerlIO_printf(Perl_debug_log, "PVNV%s\n", s);
	break;
    case SVt_PVBM:
	PerlIO_printf(Perl_debug_log, "PVBM%s\n", s);
	break;
    case SVt_PVMG:
	PerlIO_printf(Perl_debug_log, "PVMG%s\n", s);
	break;
    case SVt_PVLV:
	PerlIO_printf(Perl_debug_log, "PVLV%s\n", s);
	break;
    case SVt_PVAV:
	PerlIO_printf(Perl_debug_log, "PVAV%s\n", s);
	break;
    case SVt_PVHV:
	PerlIO_printf(Perl_debug_log, "PVHV%s\n", s);
	break;
    case SVt_PVCV:
	PerlIO_printf(Perl_debug_log, "PVCV%s\n", s);
	break;
    case SVt_PVGV:
	PerlIO_printf(Perl_debug_log, "PVGV%s\n", s);
	break;
    case SVt_PVFM:
	PerlIO_printf(Perl_debug_log, "PVFM%s\n", s);
	break;
    case SVt_PVIO:
	PerlIO_printf(Perl_debug_log, "PVIO%s\n", s);
	break;
    default:
	PerlIO_printf(Perl_debug_log, "UNKNOWN%s\n", s);
	return;
    }
    if (type >= SVt_PVIV || type == SVt_IV)
	PerlIO_printf(Perl_debug_log, "  IV = %ld\n", (long)SvIVX(sv));
    if (type >= SVt_PVNV || type == SVt_NV) {
	SET_NUMERIC_STANDARD();
	PerlIO_printf(Perl_debug_log, "  NV = %.*g\n", DBL_DIG, SvNVX(sv));
    }
    if (SvROK(sv)) {
	PerlIO_printf(Perl_debug_log, "  RV = 0x%lx\n", (long)SvRV(sv));
	mysv_dump(SvRV(sv));
	return;
    }
    if (type < SVt_PV)
	return;
    if (type <= SVt_PVLV) {
	if (SvPVX(sv))
	    PerlIO_printf(Perl_debug_log, "  PV = 0x%lx \"%s\"\n  CUR = %ld\n  LEN = %ld\n",
		(long)SvPVX(sv), SvPVX(sv), (long)SvCUR(sv), (long)SvLEN(sv));
	else
	    PerlIO_printf(Perl_debug_log, "  PV = 0\n");
    }
    if (type >= SVt_PVMG) {
	if (SvMAGIC(sv)) {
	    PerlIO_printf(Perl_debug_log, "  MAGIC = 0x%lx\n", (long)SvMAGIC(sv));
	}
	if (SvSTASH(sv))
	    PerlIO_printf(Perl_debug_log, "  STASH = \"%s\"\n", HvNAME(SvSTASH(sv)));
    }
    switch (type) {
    case SVt_PVLV:
	PerlIO_printf(Perl_debug_log, "  TYPE = %c\n", LvTYPE(sv));
	PerlIO_printf(Perl_debug_log, "  TARGOFF = %ld\n", (long)LvTARGOFF(sv));
	PerlIO_printf(Perl_debug_log, "  TARGLEN = %ld\n", (long)LvTARGLEN(sv));
	PerlIO_printf(Perl_debug_log, "  TARG = 0x%lx\n", (long)LvTARG(sv));
	mysv_dump(LvTARG(sv));
	break;
    case SVt_PVAV:
	PerlIO_printf(Perl_debug_log, "  ARRAY = 0x%lx\n", (long)AvARRAY(sv));
	PerlIO_printf(Perl_debug_log, "  ALLOC = 0x%lx\n", (long)AvALLOC(sv));
	PerlIO_printf(Perl_debug_log, "  FILL = %ld\n", (long)AvFILLp(sv));
	PerlIO_printf(Perl_debug_log, "  MAX = %ld\n", (long)AvMAX(sv));
	PerlIO_printf(Perl_debug_log, "  ARYLEN = 0x%lx\n", (long)AvARYLEN(sv));
	flags = AvFLAGS(sv);
	sv_setpv(d, "");
	if (flags & AVf_REAL)	sv_catpv(d, ",REAL");
	if (flags & AVf_REIFY)	sv_catpv(d, ",REIFY");
	if (flags & AVf_REUSED)	sv_catpv(d, ",REUSED");
	PerlIO_printf(Perl_debug_log, "  FLAGS = (%s)\n",
		      SvCUR(d) ? SvPVX(d) + 1 : "");
	break;
    case SVt_PVHV:
	PerlIO_printf(Perl_debug_log, "  ARRAY = 0x%lx\n",(long)HvARRAY(sv));
	PerlIO_printf(Perl_debug_log, "  KEYS = %ld\n", (long)HvKEYS(sv));
	PerlIO_printf(Perl_debug_log, "  FILL = %ld\n", (long)HvFILL(sv));
	PerlIO_printf(Perl_debug_log, "  MAX = %ld\n", (long)HvMAX(sv));
	PerlIO_printf(Perl_debug_log, "  RITER = %ld\n", (long)HvRITER(sv));
	PerlIO_printf(Perl_debug_log, "  EITER = 0x%lx\n",(long) HvEITER(sv));
	if (HvPMROOT(sv))
	    PerlIO_printf(Perl_debug_log, "  PMROOT = 0x%lx\n",(long)HvPMROOT(sv));
	if (HvNAME(sv))
	    PerlIO_printf(Perl_debug_log, "  NAME = \"%s\"\n", HvNAME(sv));
	break;
    case SVt_PVCV:
	if (SvPOK(sv))
	    PerlIO_printf(Perl_debug_log, "  PROTOTYPE = \"%s\"\n", SvPV(sv,na));
	/* FALL THROUGH */
    case SVt_PVFM:
	PerlIO_printf(Perl_debug_log, "  STASH = 0x%lx\n", (long)CvSTASH(sv));
	PerlIO_printf(Perl_debug_log, "  START = 0x%lx\n", (long)CvSTART(sv));
	PerlIO_printf(Perl_debug_log, "  ROOT = 0x%lx\n", (long)CvROOT(sv));
	PerlIO_printf(Perl_debug_log, "  XSUB = 0x%lx\n", (long)CvXSUB(sv));
	PerlIO_printf(Perl_debug_log, "  XSUBANY = %ld\n", (long)CvXSUBANY(sv).any_i32);
	PerlIO_printf(Perl_debug_log, "  GV = 0x%lx", (long)CvGV(sv));
	if (CvGV(sv) && GvNAME(CvGV(sv))) {
	    PerlIO_printf(Perl_debug_log, "  \"%s\"\n", GvNAME(CvGV(sv)));
	} else {
	    PerlIO_printf(Perl_debug_log, "\n");
	}
	PerlIO_printf(Perl_debug_log, "  FILEGV = 0x%lx\n", (long)CvFILEGV(sv));
	PerlIO_printf(Perl_debug_log, "  DEPTH = %ld\n", (long)CvDEPTH(sv));
	PerlIO_printf(Perl_debug_log, "  PADLIST = 0x%lx\n", (long)CvPADLIST(sv));
	PerlIO_printf(Perl_debug_log, "  OUTSIDE = 0x%lx\n", (long)CvOUTSIDE(sv));
#ifdef USE_THREADS
	PerlIO_printf(Perl_debug_log, "  MUTEXP = 0x%lx\n", (long)CvMUTEXP(sv));
	PerlIO_printf(Perl_debug_log, "  OWNER = 0x%lx\n", (long)CvOWNER(sv));
#endif /* USE_THREADS */
	PerlIO_printf(Perl_debug_log, "  FLAGS = 0x%lx\n",
		      (unsigned long)CvFLAGS(sv));
	if (type == SVt_PVFM)
	    PerlIO_printf(Perl_debug_log, "  LINES = %ld\n", (long)FmLINES(sv));
	break;
    case SVt_PVGV:
	PerlIO_printf(Perl_debug_log, "  NAME = \"%s\"\n", GvNAME(sv));
	PerlIO_printf(Perl_debug_log, "  NAMELEN = %ld\n", (long)GvNAMELEN(sv));
	PerlIO_printf(Perl_debug_log, "  STASH = \"%s\"\n", HvNAME(GvSTASH(sv)));
	PerlIO_printf(Perl_debug_log, "  GP = 0x%lx\n", (long)GvGP(sv));
	PerlIO_printf(Perl_debug_log, "    SV = 0x%lx\n", (long)GvSV(sv));
	PerlIO_printf(Perl_debug_log, "    REFCNT = %ld\n", (long)GvREFCNT(sv));
	PerlIO_printf(Perl_debug_log, "    IO = 0x%lx\n", (long)GvIOp(sv));
	PerlIO_printf(Perl_debug_log, "    FORM = 0x%lx\n", (long)GvFORM(sv));
	PerlIO_printf(Perl_debug_log, "    AV = 0x%lx\n", (long)GvAV(sv));
	PerlIO_printf(Perl_debug_log, "    HV = 0x%lx\n", (long)GvHV(sv));
	PerlIO_printf(Perl_debug_log, "    CV = 0x%lx\n", (long)GvCV(sv));
	PerlIO_printf(Perl_debug_log, "    CVGEN = 0x%lx\n", (long)GvCVGEN(sv));
	PerlIO_printf(Perl_debug_log, "    LASTEXPR = %ld\n", (long)GvLASTEXPR(sv));
	PerlIO_printf(Perl_debug_log, "    LINE = %ld\n", (long)GvLINE(sv));
	PerlIO_printf(Perl_debug_log, "    FILEGV = 0x%lx\n", (long)GvFILEGV(sv));
	PerlIO_printf(Perl_debug_log, "    EGV = 0x%lx\n", (long)GvEGV(sv));
	break;
    case SVt_PVIO:
	PerlIO_printf(Perl_debug_log, "  IFP = 0x%lx\n", (long)IoIFP(sv));
	PerlIO_printf(Perl_debug_log, "  OFP = 0x%lx\n", (long)IoOFP(sv));
	PerlIO_printf(Perl_debug_log, "  DIRP = 0x%lx\n", (long)IoDIRP(sv));
	PerlIO_printf(Perl_debug_log, "  LINES = %ld\n", (long)IoLINES(sv));
	PerlIO_printf(Perl_debug_log, "  PAGE = %ld\n", (long)IoPAGE(sv));
	PerlIO_printf(Perl_debug_log, "  PAGE_LEN = %ld\n", (long)IoPAGE_LEN(sv));
	PerlIO_printf(Perl_debug_log, "  LINES_LEFT = %ld\n", (long)IoLINES_LEFT(sv));
	PerlIO_printf(Perl_debug_log, "  TOP_NAME = \"%s\"\n", IoTOP_NAME(sv));
	PerlIO_printf(Perl_debug_log, "  TOP_GV = 0x%lx\n", (long)IoTOP_GV(sv));
	PerlIO_printf(Perl_debug_log, "  FMT_NAME = \"%s\"\n", IoFMT_NAME(sv));
	PerlIO_printf(Perl_debug_log, "  FMT_GV = 0x%lx\n", (long)IoFMT_GV(sv));
	PerlIO_printf(Perl_debug_log, "  BOTTOM_NAME = \"%s\"\n", IoBOTTOM_NAME(sv));
	PerlIO_printf(Perl_debug_log, "  BOTTOM_GV = 0x%lx\n", (long)IoBOTTOM_GV(sv));
	PerlIO_printf(Perl_debug_log, "  SUBPROCESS = %ld\n", (long)IoSUBPROCESS(sv));
	PerlIO_printf(Perl_debug_log, "  TYPE = %c\n", IoTYPE(sv));
	PerlIO_printf(Perl_debug_log, "  FLAGS = 0x%lx\n", (long)IoFLAGS(sv));
	break;
    }
}
