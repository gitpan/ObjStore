// Switch to -*-c++-*- mode please!
/*
Copyright (c) 1997 Joshua Nathaniel Pritikin.  All rights reserved.
This package is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.
*/

#include <assert.h>
#include <string.h>
#include "osperl.hh"
#include <ostore/coll.hh>

//#define DEBUG_OSSV_ASSIGN 1
//#define DEBUG_REFCNT 1
//#define DEBUG_BRIDGE 1

/*--------------------------------------------- typemap services */

// Can we croak if failure?  Try to factor more!  XXX

ossv_bridge *osperl::sv_2bridge(SV *nval)
{
// Is tied?  Examine tied object, extract ossv_bridge from '~'
// Is OSSV in a PVMG?

  assert(nval);
  if (!SvROK(nval)) return 0;
  nval = SvRV(nval);
  assert(nval);

  if (SvMAGICAL(nval) && (SvTYPE(nval) == SVt_PVHV || SvTYPE(nval) == SVt_PVAV)) {

    MAGIC *magic = mg_find(nval, '~');
    if (!magic) {
      //      warn("~ magic missing");
      return 0;
    }
    SV *mgobj = (SV*) magic->mg_obj;
    assert(mgobj);
    if (!sv_isobject(mgobj)) {
      //      warn("junk attached via ~ magic");
      return 0;
    }
    ossv_bridge *br = (ossv_bridge*) SvIV((SV*)SvRV(mgobj));
    assert(br);
    return br;

  } else if (SvOBJECT(nval) && SvTYPE(nval) == SVt_PVMG) {

    ossv_bridge *br = (ossv_bridge*) SvIV(nval);
    assert(br);
    return br;

  }
  return 0;
}

os_segment *osperl::sv_2segment(SV *sv)
{
  if (sv_isa(sv, "ObjStore::Segment")) return (os_segment*) SvIV((SV*)SvRV(sv));
  if (sv_isa(sv, "ObjStore::Database"))
    return ((os_database*) SvIV((SV*)SvRV(sv)))->get_default_segment();

  ossv_bridge *br = osperl::sv_2bridge(sv);
  if (!br) croak("osperl::sv_2segment(SV*): must be persistent object");
  return os_segment::of(br->get_location());
}

SV *osperl::stargate=0;
ossv_bridge *osperl::force_sv_2bridge(os_segment *seg, SV *nval)
{
  dSP ;
  // You must use ENTER / LEAVE around this function.
  //  ENTER ;
  //  SAVETMPS ;
  PUSHMARK(sp);
  XPUSHs(sv_setref_pv(sv_newmortal(), "ObjStore::Segment", seg));
  XPUSHs(nval);
  PUTBACK ;
  assert(osperl::stargate);
  int count = perl_call_sv(osperl::stargate, G_SCALAR);
  assert(count==1);
  SPAGAIN ;
  ossv_bridge *br = osperl::sv_2bridge(POPs);
  PUTBACK ;
  //  FREETMPS ;
  //  LEAVE ;
  if (!br) croak("ObjStore::stargate returned useless junk");
  //  warn("stargate returned:");
  //  br->dump();
  return br;
}

int osperl::rethrow_exceptions;
int osperl::enable_blessings;
HV* osperl::CLASSLOAD;

void osperl::boot_thread()
{
  rethrow_exceptions = 1;
  tie_objects = 1;
  enable_blessings = 1;
  CLASSLOAD = perl_get_hv("ObjStore::CLASSLOAD", FALSE);
  assert(CLASSLOAD);
}

int osperl::tie_objects;
SV *osperl::wrap_object(OSSVPV *ospv)
{
  char *CLASS = enable_blessings? ospv->get_blessing() : ospv->base_class();
  ossv_bridge *bridge = ospv->_new_bridge(ospv);
  SV *rv;

  switch (ospv->get_perl_type()) {
  case SVt_PVMG:
    rv = sv_setref_pv(sv_newmortal(), CLASS, (void*)bridge);
    break;
  case SVt_PVHV:
  case SVt_PVAV:{
    // This typemap scares me.  Will it work everywhere? XXX
      SV *tied;
      if (ospv->get_perl_type() == SVt_PVHV) {
	tied = sv_2mortal((SV*) newHV());	// %tied
      } else {
	tied = sv_2mortal((SV*) newAV());	// @tied
      }
      rv = newRV(tied);				// $rv = \tied
      --SvREFCNT(SvRV(rv));			// undo ref

      HV* stash = gv_stashpv(CLASS, TRUE);	// bless $rv, CLASS
      assert(stash);
      (void)sv_bless(rv, stash);
      
      if (osperl::tie_objects) {
	sv_magic(tied, rv, 'P', Nullch, 0);	// tie tied, CLASS, $rv
	MAGIC *tie_mg = mg_find(tied, 'P');	// undo tie refcnt (yikes!)
	assert(tie_mg);
	tie_mg->mg_flags &= ~(MGf_REFCOUNTED);
	--SvREFCNT(rv);
      }

      SV *mgobj = sv_setref_pv(sv_newmortal(),	// magic %tied, '~', $mgobj
			       "ObjStore::Bridge",
			       bridge);
      sv_magic(SvRV(rv), mgobj, '~', Nullch, 0);
      break;}
  default:
      croak("osperl::ossv_2sv: unknown perl type (%d)", ospv->get_perl_type());
  }
  return rv;
}

SV *osperl::ospv_2sv(OSSVPV *pv)
{
  if (!pv) return &sv_undef;
  return osperl::wrap_object(pv);
}

//    if (GIMME_V == G_VOID) return 0;  // fold into ossv_2sv? XXX
SV *osperl::ossv_2sv(OSSV *ossv)
{
  if (!ossv) return &sv_undef;
  switch (ossv->natural()) {
  case ossv_undef: return &sv_undef;
  case ossv_iv:    return newSViv(((OSPV_iv*)ossv->vptr)->iv);
  case ossv_nv:    return newSVnv(((OSPV_nv*)ossv->vptr)->nv);
  case ossv_pv:    return newSVpv((char*) ossv->vptr, 0);
  case ossv_obj:   return osperl::wrap_object((OSSVPV*) ossv->vptr);
  default:
    warn("OSSV %s is not implemented", ossv->type_2pv());
    return &sv_undef;
  }
}

SV *osperl::hkey_2sv(hkey *hk)
{
  // ignore zero termination for easy coersion to numbers
  if (!hk || !hk->pv || hk->len < 2) return &sv_undef;
  return sv_2mortal(newSVpv(hk->pv, hk->len-1));
}

void osperl::push_key_ossv(hkey *hk, OSSV *hv)
{
  if (!hk && !hv) return;
  assert(hk && hv);
  dSP;
  EXTEND(SP, 2);
  PUSHs(osperl::hkey_2sv(hk));
  PUSHs(osperl::ossv_2sv(hv));
  PUTBACK;
}

void osperl::push_ospv(OSSVPV *pv)
{
  if (!pv) return;
  dSP;
  PUSHs(osperl::ospv_2sv(pv));
  PUTBACK;
}

/*--------------------------------------------- ossv_bridge */

// bridge is built from north to south
ossv_bridge *osperl::bridge_top = 0;

void osperl::destroy_bridge()
{
  while (bridge_top) { bridge_top->invalidate(); }
  assert(bridge_top==0);
}

ossv_bridge::ossv_bridge(OSSVPV *_pv)
  : pv(_pv)
{
  assert(pv);
#if DEBUG_BRIDGE
  warn("ossv_bridge 0x%x->new(%s=0x%x)", this, _pv->base_class(), _pv);
#endif
  if (osperl::is_update_txn) pv->REF_inc();

  prev = 0;
  if (osperl::bridge_top) {
    osperl::bridge_top->prev = this;
    next = osperl::bridge_top;
    osperl::bridge_top = this;
  } else {
    next = 0;
    osperl::bridge_top = this;
  }
}

// Must be able to remove itself from the list
void ossv_bridge::invalidate()
{
  if (!pv) return;
#if DEBUG_BRIDGE
  warn("ossv_bridge 0x%x->invalidate(pv=0x%x) updt=%d ok=%d",
       this, pv, osperl::is_update_txn, osperl::txn_is_ok);
#endif
  if (osperl::is_update_txn && osperl::txn_is_ok) pv->REF_dec();
  pv=0;

  if (next) next->prev = prev;
  if (prev) prev->next = next;
  if (osperl::bridge_top == this) {
    if (next) osperl::bridge_top = next;
    else osperl::bridge_top = prev;
  }
}

ossv_bridge::~ossv_bridge()
{ invalidate(); }

void ossv_bridge::dump()
{ warn("ossv_bridge=0x%x pv=0x%x", this, pv); }

OSSV *osperl::plant_sv(os_segment *seg, SV *nval)
{
  OSSV *ossv=0;
  ossv_bridge *br = osperl::sv_2bridge(nval);
  if (br) {
    OSSVPV *pv = br->ospv();
    assert(pv);
    ossv = new(os_segment::of(pv), OSSV::get_os_typespec()) OSSV(pv);
  } else {
    ossv = new(seg, OSSV::get_os_typespec()) OSSV(nval);
  }
  assert(ossv);
  return ossv;
}

OSSVPV *ossv_bridge::ospv()
{ return pv; }

void *ossv_bridge::get_location()
{ return pv; }

/*--------------------------------------------- OSSV */

OSSV::OSSV() : _type(ossv_undef), _refs(0)
{}

OSSV::OSSV(SV *nval) : _type(ossv_undef), _refs(0)
{ this->operator=(nval); }

OSSV::OSSV(OSSV *nval) : _type(ossv_undef), _refs(0)
{ *this = *nval; }

OSSV::OSSV(OSSVPV *nval) : _type(ossv_undef), _refs(0)
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

// Should always try to store numbers in the smallest space that
// preserves precision.  Is this right?  XXX
OSSV *OSSV::operator=(SV *nval)
{
  ossv_bridge *br = osperl::sv_2bridge(nval);
  if (br) { s(br); return this; }

  char *tmp; unsigned tmplen;

  if (SvIOKp(nval)) {		//try private
    s((os_int32) SvIV(nval));
  } else if (SvNOKp(nval)) {
    s(SvNV(nval));
  } else if (SvPOKp(nval)) {
    tmp = SvPV(nval, tmplen);
    s(tmp, tmplen);
  } else if (SvIOK(nval)) {	//try coersion
    s((os_int32) SvIV(nval));
  } else if (SvNOK(nval)) {
    s(SvNV(nval));
  } else if (SvPOK(nval)) {
    tmp = SvPV(nval, tmplen);
    s(tmp, tmplen);
  } else if (! SvOK(nval)) {
    set_undef();
  } else {
    ENTER ;
    SAVETMPS ;
    s(osperl::force_sv_2bridge(os_segment::of(this), nval));
    FREETMPS ;
    LEAVE ;
  }
  return this;
}

OSSV *OSSV::operator=(const OSSV &nval)		// i hate const
{ s( (OSSV*) &nval); return this; }

OSSV *OSSV::operator=(OSSV &nval)
{ s(&nval); return this; }

int OSSV::operator==(OSSV &nval)
{
  if (natural() != nval.natural()) return 0;
  switch (natural()) {
  case ossv_undef: return 1;
  case ossv_iv:    return ((OSPV_iv*)vptr)->iv == ((OSPV_iv*)nval.vptr)->iv;
  case ossv_nv:    return ((OSPV_nv*)vptr)->nv == ((OSPV_nv*)nval.vptr)->nv;
  case ossv_pv:    return (strcmp((char*)vptr, (char*)nval.vptr)==0);
  case ossv_obj:   return vptr == nval.vptr;
  default:         die("negligent developer");
  };
}

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
#ifdef DEBUG_OSSV_ASSIGN
    warn("OSSV(0x%x)->morph(pv): deleting string '%s' 0x%x",
	 this, vptr, vptr);
#endif
    delete [] ((char*)vptr);
    vptr = 0;
    break;

  case ossv_obj: break;

  default: croak("OSSV->morph type %s unknown", OSSV::type_2pv( (ossvtype)_type));
  }
  _type = nty;
  return 1;
}

void OSSV::set_undef()
{ morph(ossv_undef); }

void OSSV::s(os_int32 nval)
{
  if (morph(ossv_iv)) {
    vptr = new(os_segment::of(this), OSPV_iv::get_os_typespec()) OSPV_iv;
  }
  ((OSPV_iv*)vptr)->iv = nval;
#ifdef DEBUG_OSSV_ASSIGN
  warn("OSSV(0x%x)->s(i:%d)", this, nval);
#endif
}

void OSSV::s(double nval)
{
  if (morph(ossv_nv)) {
    vptr = new(os_segment::of(this), OSPV_nv::get_os_typespec()) OSPV_nv;
  }
  ((OSPV_nv*)vptr)->nv = nval;
#ifdef DEBUG_OSSV_ASSIGN
  warn("OSSV(0x%x)->s(n:%f)", this, nval);
#endif
}

// nval must be null terminated or the length must be specified.
// Since the length is not stored, a null terminated is added if not found.
void OSSV::s(char *nval, os_unsigned_int32 nlen)
{
  if (nlen==0) nlen = strlen(nval)+1;
  int neednull = nval[nlen-1]!=0;
//  warn("OSSV::s - prior type = %d", _type);
  if (!morph(ossv_pv)) {
#ifdef DEBUG_OSSV_ASSIGN
    warn("OSSV(0x%x)->s(): deleting string 0x%x", this, vptr);
#endif
    delete [] ((char*)vptr);
    vptr = 0;
  }
  char *str = new(os_segment::of(this), os_typespec::get_char(),
		  nlen+neednull) char[nlen+neednull];
  memcpy(str, nval, nlen);
  if (neednull) str[nlen] = 0;
  vptr = str;
#ifdef DEBUG_OSSV_ASSIGN
  warn("OSSV(0x%x)->s(%s): alloc 0x%x", this, (char*) vptr, str);
#endif
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
  case ossv_iv: s(((OSPV_iv*)nval->vptr)->iv); break;
  case ossv_nv: s(((OSPV_nv*)nval->vptr)->nv); break;
  case ossv_pv: s((char*) nval->vptr, 0); break;
  case ossv_obj: s((OSSVPV*) nval->vptr); break;
  default: croak("OSSV::s(OSSV*): assertion failed");
  }
}

void OSSV::s(OSSVPV *nval)
{ 
  assert(nval);
#ifdef DEBUG_OSSV_ASSIGN
  warn("OSSV(0x%x)->s(%s=0x%x)", this, nval->base_class(), nval);
#endif
  if (morph(ossv_obj)) {
    PvREF_inc(nval);
  } else if (vptr != nval) {
    PvREF_dec();
    PvREF_inc(nval);
  }
}

os_int32 OSSV::as_iv()
{
  switch (natural()) {
    case ossv_iv: return ((OSPV_iv*)vptr)->iv;
    case ossv_nv: return (I32) ((OSPV_nv*)vptr)->nv;
    default:
      warn("SV %s has no int representation", type_2pv());
      return 0;
  }
}

double OSSV::as_nv()
{
  switch (natural()) {
    case ossv_iv: return ((OSPV_iv*)vptr)->iv;
    case ossv_nv: return ((OSPV_nv*)vptr)->nv;
    default:
      warn("SV %s has no double representation", type_2pv());
      return 0;
  }
}

char OSSV::strrep[32];  // temporary space for string representation

char *OSSV::as_pv()     // returned string does not need to be freed
{
  switch (natural()) {
    case ossv_iv:   sprintf(strrep, "%ld", ((OSPV_iv*)vptr)->iv); break;
    case ossv_nv:   sprintf(strrep, "%f", ((OSPV_nv*)vptr)->nv); break;
    case ossv_pv:   return (char*) vptr;
    case ossv_obj:
      sprintf(strrep, "%s=0x%lx", ((OSSVPV*)vptr)->get_blessing(), vptr);
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
   case ossv_iv:    return "int";
   case ossv_nv:    return "double";
   case ossv_pv:    return "string";
   case ossv_obj:    return "OBJECT";
   default: croak("OSSV::type_2pv: assertion failed (%d)", ty);
  }
};

char *OSSV::type_2pv()
{
  switch (natural()) {
   case ossv_undef: return "undef";
   case ossv_iv:    return "int";
   case ossv_nv:    return "double";
   case ossv_pv:    return "string";
   case ossv_obj:
     sprintf(strrep, "%s=0x%lx", ((OSSVPV*)vptr)->get_blessing(), vptr);
     return strrep;
   default: croak("OSSV::type_2pv: assertion failed (%d)", natural());
  }
}

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

hent *hent::operator=(const hent &nval)
{
  hk.operator=(nval.hk); hv.operator=( (OSSV&) nval.hv);
  return this;
}

/*--------------------------------------------- OSSVPV */

OSSVPV::OSSVPV()
  : _refs(0), classname(0)
{
#if DEBUG_REFCNT
  warn("new OSSVPV(0x%x)", this);
#endif
}
OSSVPV::~OSSVPV()
{
#ifdef DEBUG_REFCNT
  warn("~OSSVPV(0x%x)", this);
#endif
  classname=0;
}

// Class names are allocated in _get_persistent_raw_string.
// They are not reference counted or deallocated automatically.
void OSSVPV::_bless(char *clname)
{
  //  warn("_bless 0x%x to %s", this, clname);
  if (strEQ(clname, base_class())) {
    classname = 0;
    return;
  }

  dSP ;
  ENTER ;
  SAVETMPS ;
  PUSHMARK(sp);
  XPUSHs(sv_setref_pv(sv_newmortal(), "ObjStore::Database", os_database::of(this)));
  XPUSHs(sv_2mortal(newSVpv(clname, 0)));
  PUTBACK ;
  int count = perl_call_method("_get_persistent_raw_string", G_SCALAR);
  assert(count==1);
  SPAGAIN ;

  SV *rawsv = POPs;
  if (SvROK(rawsv)) {
    IV tmp = SvIV((SV*)SvRV(rawsv));
    classname = (char *) tmp;
  }
  else croak("_get_persistent_raw_string returned <bogus>");

  PUTBACK ;
  FREETMPS ;
  LEAVE ;
}

char *OSSVPV::get_blessing()
{
  char *CLASS = classname;
  if (CLASS) {
    int cl = strlen(CLASS);       // cache in the database? XXX
    
    if (osperl::enable_blessings &&
	!hv_exists(osperl::CLASSLOAD, CLASS, cl)) {
      SV *clsv = sv_2mortal(newSVpv(CLASS, cl));
      SV *ldr = perl_get_sv("ObjStore::CLASSLOAD", 0);
      assert(ldr);
      dSP ;
      ENTER ;
      SAVETMPS ;
      PUSHMARK(sp);
      XPUSHs(sv_setref_pv(sv_newmortal(), "ObjStore::Database",
			  os_database::of(this)));
      XPUSHs(clsv);
      PUTBACK ;
      perl_call_sv(ldr, G_DISCARD);
      FREETMPS ;
      LEAVE ;
    }
  } else {
    CLASS = base_class();
  }
  assert(CLASS);
  return CLASS;
}

const os_unsigned_int32 OSSVPV::MAX_REFCNT = 4294967285UL;    // 2**32 - 10
void OSSVPV::REF_inc() {
  _refs++;
  if (_refs > MAX_REFCNT) croak("OSSVPV::REF_inc(): _refs > %ud", MAX_REFCNT);
#ifdef DEBUG_REFCNT
  warn("OSSVPV(0x%x)->REF_inc() to %d", this, _refs);
#endif
}

void OSSVPV::REF_dec() { 
  _refs--;
#ifdef DEBUG_REFCNT
  warn("OSSVPV(0x%x)->REF_dec() to %d", this, _refs);
#endif
  if (_refs == 0) {
    delete this;
  }
}

int OSSVPV::get_perl_type()
{ return SVt_PVMG; }

char *OSSVPV::base_class()
{ croak("OSSVPV(0x%x)->base_class() must be overridden", this); return 0; }

// Usually will override, but here's a default.
ossv_bridge *OSSVPV::_new_bridge(OSSVPV *_pv)
{ return new ossv_bridge(_pv); }

// common to containers
char *OSSVPV::_get_raw_string(char *key)
{ croak("OSSVPV(0x%x)->_get_raw_string",this); return 0; }
double OSSVPV::_percent_filled() { return -1; }
OSPV_Cursor *OSSVPV::new_cursor(os_segment *seg)
{ croak("OSSVPV(0x%x)->new_cursor(seg)",this); return 0; }

// common to cursors
char *OSPV_Cursor::base_class()
{ return "ObjStore::Cursor"; }
SV *OSPV_Cursor::focus()
{ croak("OSPV_Cursor(0x%x)->focus()", this); return &sv_undef; }
int OSPV_Cursor::more()
{ croak("OSPV_Cursor(0x%x)->more()", this); return 0; }
void OSPV_Cursor::first()
{ croak("OSPV_Cursor(0x%x)->first()", this); }
void OSPV_Cursor::next()
{ croak("OSPV_Cursor(0x%x)->next()", this); }
void OSPV_Cursor::prev()
{ croak("OSPV_Cursor(0x%x)->prev()", this); }
void OSPV_Cursor::last()
{ croak("OSPV_Cursor(0x%x)->last()", this); }
