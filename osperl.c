// Switch to -*-c++-*- mode please!
/*
Copyright (c) 1997 Joshua Nathaniel Pritikin.  All rights reserved.
This package is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.
*/

#include <assert.h>
#include <string.h>
#include "osperl.hh"

/*--------------------------------------------- registration */

osperl_ospec *osperl_ospec::operator=(const osperl_ospec &t1)
{ memcpy(this, &t1, sizeof(osperl_ospec)); return this; }

SPList < osperl_ospec > *osperl::ospecs = 0;

void osperl::register_spec(char *name, MkOSPerlObj_t fun)
{
  if (!ospecs) ospecs = new SPList<osperl_ospec> (10, 8);
  osperl_ospec spec;
  spec.name = name;
  spec.fun = (void *) fun;
  ospecs->push(spec);
}

/*--------------------------------------------- typemap services */

// Is tied?  Examine tied object, extract ossv_magic from '~'
// Is OSSV in a PVMG?
// Can we croak if failure? XXX
ossv_magic *osperl::sv_2magic(SV *nval)
{
  assert(nval);
  if (SvROK(nval)) nval = SvRV(nval);
  assert(nval);

  if (SvMAGICAL(nval) && (SvTYPE(nval) == SVt_PVHV || SvTYPE(nval) == SVt_PVAV)) {

    MAGIC *magic = mg_find(nval, '~');
    if (!magic) return 0;
    SV *mgobj = (SV*) magic->mg_obj;
    assert(mgobj);
    if (!sv_isobject(mgobj)) return 0;
    ossv_magic *mg = (ossv_magic*) SvIV((SV*)SvRV(mgobj));
    assert(mg);
    return mg;

  } else if (SvOBJECT(nval) && SvTYPE(nval) == SVt_PVMG) {

    ossv_magic *mg = (ossv_magic*) SvIV(nval);
    assert(mg);
    return mg;

  }
  return 0;
}

os_segment *osperl::sv_2segment(SV *sv)
{
  if (sv_isa(sv, "ObjStore::Segment")) return (os_segment*) SvIV((SV*)SvRV(sv));
  if (sv_isa(sv, "ObjStore::Database"))
    return ((os_database*) SvIV((SV*)SvRV(sv)))->get_default_segment();

  ossv_magic *mg = osperl::sv_2magic(sv);
  if (!mg) croak("Allocation area outside of persistent memory");
  return os_segment::of(mg->get_location());
}

SV *osperl::gateway=0;
ossv_magic *osperl::force_sv_2magic(os_segment *seg, SV *nval)
{
  dSP ;
  // You must use ENTER / LEAVE around this function.
  //  ENTER ;
  //  SAVETMPS ;
  PUSHMARK(sp);
  XPUSHs(sv_setref_pv(sv_newmortal(), "ObjStore::Segment", seg));
  XPUSHs(nval);
  PUTBACK ;
  assert(osperl::gateway);
  int count = perl_call_sv(osperl::gateway, G_SCALAR);
  assert(count==1);
  SPAGAIN ;
  ossv_magic *mg = osperl::sv_2magic(POPs);
  PUTBACK ;
  //  FREETMPS ;
  //  LEAVE ;
  if (!mg) croak("ObjStore::gateway returned useless junk");
  //  warn("gateway returned:");
  //  mg->dump();
  return mg;
}

int osperl::enable_blessings = 1;
SV *osperl::wrap_object(OSSV *ossv, OSSVPV *ospv)
{
  char *CLASS = enable_blessings? ospv->get_blessing() : ospv->base_class();
  ossv_magic *magic = ospv->NEW_MAGIC(ossv, ospv);
  SV *rv;

  switch (ospv->get_perl_type()) {
  case SVt_PVMG:
    rv = sv_setref_pv(sv_newmortal(), CLASS, (void*)magic);
    break;
  case SVt_PVHV:
  case SVt_PVAV:{
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
      
      sv_magic(tied, rv, 'P', Nullch, 0);	// tie tied, CLASS, $rv
      MAGIC *tie_mg = mg_find(tied, 'P');	// undo tie refcnt (yikes!)
      assert(tie_mg);
      tie_mg->mg_flags &= ~(MGf_REFCOUNTED);
      --SvREFCNT(rv);
      SV *mgobj = sv_setref_pv(sv_newmortal(),	// magic %tied, '~', $mgobj
			       "ObjStore::Magic",
			       magic);
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
  return osperl::wrap_object(0, pv);
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
  case ossv_obj:   return osperl::wrap_object(ossv, (OSSVPV*) ossv->vptr);
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

/*--------------------------------------------- ossv_magic */

ossv_magic::ossv_magic(OSSV *_sv, OSSVPV *_pv)
  : sv(_sv), pv(_pv)
{ //warn("new ossv_magic 0x%x", this);
}

ossv_magic::~ossv_magic()
{
#if DEBUG_DESTROY
  warn("ossv_magic 0x%x->DESTROY", this);
#endif
  if (sv) sv->REF_check();
    //    if (pv) pv->REF_check();  ??
}

void ossv_magic::dump()
{
  if (sv) {
    warn("ossv_magic=0x%x sv=%s pv=0x%x", this, sv->as_pv(), pv);
  } else {
    warn("ossv_magic=0x%x pv=0x%x", this, pv);
  }
}

OSSV *ossv_magic::force_ossv()
{
  if (sv) return sv;
  if (!pv) croak("ossv_magic::force_ossv(): assertion failed");
  OSSV *ossv = new(os_segment::of(pv), OSSV::get_os_typespec()) OSSV(pv);
  return ossv;
}

OSSVPV *ossv_magic::ospv()
{
  if (pv) return pv;
  if (sv && sv->PvREFok()) return (OSSVPV*) sv->vptr;
  return 0;
}

void *ossv_magic::get_location()
{
  if (pv) return pv;
  if (sv) return sv->PvREFok()? sv->vptr : sv;
  croak("ossv_magic invalid");
}

/*--------------------------------------------- OSSV */

// Assume allocated inside an array (_refs=1).  We must reset to
// zero if the context is not an array.
OSSV::OSSV() : _refs(1), _type(ossv_undef)
{}

OSSV::OSSV(SV *nval) : _refs(0), _type(ossv_undef)
{ this->operator=(nval); }

OSSV::OSSV(OSSV *nval) : _refs(0), _type(ossv_undef)
{ *this = *nval; }

OSSV::OSSV(OSSVPV *nval) : _refs(0), _type(ossv_undef)
{ s(nval); }

OSSV::~OSSV()
{ set_undef(); }

const os_unsigned_int16 OSSV::MAX_REFCNT = 65526;    // 2**16 - 10
OSSV *OSSV::REF_inc()
{
  if (_refs > MAX_REFCNT) {
    OSSV *ossv = new(os_segment::of(this), OSSV::get_os_typespec()) OSSV(this);
    warn("OSSV 0x%x maximum refcnt exceeded (%d) - use $copy2=$copy instead of $copy=$ref",
	 this, _refs, ossv);
    ossv->_refs++;
    return ossv;
  }
  _refs++;
#ifdef DEBUG_REFCNT
  warn("OSSV::REF_inc() 0x%x to %d", this, _refs);
#endif
  return this;
}

void OSSV::REF_dec()
{
  _refs--;
#ifdef DEBUG_REFCNT
  warn("OSSV::REF_dec() 0x%x to %d", this, _refs);
#endif
  if (_refs <= 0) delete this;
}

// Transient pointers are references to the underlier. However,
// refcnts must not change during read-only transactions so we
// cannot do refcnts from transient references.  At most, we can check
// for refcnt==0 during update transactions, as below.
void OSSV::REF_check()
{
  os_transaction *xion = os_transaction::get_current();
  if (xion && xion->get_type() == os_transaction::update) {
#if (DEBUG_REFCNT || DEBUG_DESTROY)
    warn("OSSV::REF_check() 0x%x at %d", this, _refs);
#endif
    if (_refs <= 0) delete this;
  }
}

int OSSV::PvREFok()
{ return natural() == ossv_obj; }

OSSVPV *OSSV::get_ospv()
{
  if (natural() != ossv_obj) croak("THIS=%s is not an object", type_2pv());
  assert(vptr);
  return (OSSVPV*)vptr;
}

void OSSV::PvREF_inc(void *nval)
{
  if (PvREFok()) {
    if (nval) vptr = nval;
    assert(vptr != 0);
    ((OSSVPV*)vptr)->REF_inc();
  }
}

void OSSV::PvREF_dec()
{
  if (PvREFok()) { ((OSSVPV*)vptr)->REF_dec(); vptr = 0; }
}

OSSV *OSSV::operator=(SV *nval)
{
  int ok=0;
  char *tmp; unsigned tmplen;	// for extracting strings
  switch (natural()) {		// try to avoid coercing in the DB
    case ossv_iv:
      if (SvIOK(nval)) { s((os_int32) SvIV(nval)); ok=1; }
      break;
    case ossv_nv:
      if (SvNOK(nval)) { s(SvNV(nval)); ok=1; }
      break;
    case ossv_pv:
      if (SvPOK(nval)) {
        tmp = SvPV(nval, tmplen);   //memory leak? XXX
        s(tmp, tmplen);
        ok=1;
      }
      break;
    default: break;
  }
  if (ok) return this;

  OSSV *ossv;
  ossv_magic *mg = osperl::sv_2magic(nval);
  if (mg) { s(mg); return this; }

  if (SvIOKp(nval)) {
    s((os_int32) SvIV(nval));
  } else if (SvNOKp(nval)) {
    s(SvNV(nval));
  } else if (SvPOKp(nval)) {
    tmp = SvPV(nval, tmplen);   //memory leak? XXX
    s(tmp, tmplen);
  } else if (! SvOK(nval)) {
    set_undef();
  } else {
    ENTER ;
    SAVETMPS ;
    s(osperl::force_sv_2magic(os_segment::of(this), nval));  //segment ok? XXX
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

// prepare to switch to new datatype
int OSSV::morph(ossvtype nty)
{
  if (_type == nty) return 0;

  if (nty == ossv_obj && _type != ossv_undef) {
    croak("Can't coerce %s to an object", type_2pv());
  }

  PvREF_dec();
  switch (_type) {
  case ossv_undef: break;
  case ossv_iv:    delete ((OSPV_iv*)vptr); vptr=0; break;
  case ossv_nv:    delete ((OSPV_nv*)vptr); vptr=0; break;

  case ossv_pv:
#ifdef DEBUG_OSSV_VALUES
    warn("OSSV::morph(%d -> %d): deleting string '%s' 0x%x", _type, nty,vptr,vptr);
#endif
    delete [] ((char*)vptr);
    vptr = 0;
    break;

  case ossv_obj: break;

  default: croak("OSSV::morph type %s unknown", OSSV::type_2pv( (ossvtype)_type));
  }
  _type = nty;
  return 1;
}

void OSSV::set_undef()
{ morph(ossv_undef); }

void OSSV::new_object(char *rep, os_unsigned_int32 cardinality)
{
  morph(ossv_obj);
  os_segment *where = os_segment::of(this);
  for (int xx=0; xx < osperl::ospecs->scalar(); xx++) {
    osperl_ospec &spec = osperl::ospecs->operator[](xx);
    if (strEQ(spec.name, rep)) {
      vptr = (*(MkOSPerlObj_t)spec.fun)(where, rep, cardinality);
      break;
    }
  }
  if (!vptr) croak("OSSV::new_object: rep %s not found", rep);
#ifdef DEBUG_MEM_OSSVPV
  warn("OSSV::new_object(%s,%d) = 0x%x", rep, cardinality, vptr);
#endif
  PvREF_inc();
}

void OSSV::s(os_int32 nval)
{
  if (morph(ossv_iv)) {
    vptr = new(os_segment::of(this), OSPV_iv::get_os_typespec()) OSPV_iv;
  }
  ((OSPV_iv*)vptr)->iv = nval;
#ifdef DEBUG_OSSV_VALUES
  warn("OSSV(0x%x) = iv(%d)", this, nval);
#endif
}

void OSSV::s(double nval)
{
  if (morph(ossv_nv)) {
    vptr = new(os_segment::of(this), OSPV_nv::get_os_typespec()) OSPV_nv;
  }
  ((OSPV_nv*)vptr)->nv = nval;
#ifdef DEBUG_OSSV_VALUES
  warn("OSSV(0x%x) = nv(%f)", this, nval);
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
#ifdef DEBUG_OSSV_VALUES
    warn("OSSV::s: deleting string 0x%x", vptr);
#endif
    delete [] ((char*)vptr);
    vptr = 0;
  }
  char *str = new(os_segment::of(this), os_typespec::get_char(),
		  nlen+neednull) char[nlen+neednull];
  memcpy(str, nval, nlen);
  if (neednull) str[nlen] = 0;
  vptr = str;
#ifdef DEBUG_OSSV_VALUES
  warn("OSSV::s(%s): alloc string 0x%x", (char*) vptr, str);
#endif
}

void OSSV::s(ossv_magic *mg)
{
  if (mg->sv) { s(mg->sv); return; }
  if (mg->pv) { s(mg->pv); return; }
  croak("OSSV::s(ossv_magic*): assertion failed");
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

// more intelligent hash needed? XXX
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
{}
OSSVPV::~OSSVPV()
{ BLESS(0); }

// Class names are allocated elsewhere and are never deallocated.
void OSSVPV::BLESS(char *nval)
{ classname=nval; }

char *OSSVPV::get_blessing()
{
  char *CLASS = classname;
  if (!CLASS) CLASS = base_class();
  assert(CLASS);
  return CLASS;
}

const os_unsigned_int32 OSSVPV::MAX_REFCNT = 4294967285UL;    // 2**32 - 10
void OSSVPV::REF_inc() {
  _refs++;
  if (_refs > MAX_REFCNT) croak("OSSVPV::REF_inc(): _refs > %ud", MAX_REFCNT);
#ifdef DEBUG_REFCNT
  warn("OSSVPV::REF_inc() 0x%x to %d", this, _refs);
#endif
}

void OSSVPV::REF_dec() { 
  _refs--;
#ifdef DEBUG_REFCNT
  warn("OSSVPV::REF_dec() 0x%x to %d", this, _refs);
#endif
  if (_refs == 0) {
//    warn("OSSVPV::REF_dec() deleting 0x%x", this);
    delete this;
  }
}

int OSSVPV::get_perl_type()
{ return SVt_PVMG; }

char *OSSVPV::base_class()
{ croak("OSSVPV::base_class() must be overridden"); return 0; }

ossv_magic *OSSVPV::NEW_MAGIC(OSSV *, OSSVPV *)
{ croak("OSSVPV::NEW_MAGIC() must be overridden"); return 0; }

// common to containers
double OSSVPV::cardinality() { croak("OSSVPV::cardinality()"); return 0; }
double OSSVPV::percent_unused() { croak("OSSVPV::percent_unused()"); return 0; }
SV *OSSVPV::FIRST(ossv_magic*) { croak("OSSVPV::FIRST"); return 0; }
SV *OSSVPV::NEXT(ossv_magic*) { croak("OSSVPV::NEXT"); return 0; }
void OSSVPV::CLEAR() { croak("OSSVPV::CLEAR"); }

// hash
OSSV *OSSVPV::FETCHp(char *) { croak("OSSVPV::FETCH"); return 0; }
SV *OSSVPV::STOREp(char *, SV *) { croak("OSSVPV::STORE"); return 0; }
void OSSVPV::DELETE(char *) { croak("OSSVPV::DELETE"); }
int OSSVPV::EXISTS(char *) { croak("OSSVPV::EXISTS"); return 0; }

// sack
SV *OSSVPV::ADD(SV *) { croak("OSSVPV::ADD"); return 0; }
int OSSVPV::CONTAINS(SV *) { croak("OSSVPV::CONTAINS"); return 0; }
void OSSVPV::REMOVE(SV *) { croak("OSSVPV::REMOVE"); }

// array (preliminary)
OSSV *OSSVPV::FETCHi(int) { croak("OSSVPV::FETCH"); return 0; }
SV *OSSVPV::STOREi(int, SV *) { croak("OSSVPV::STORE"); return 0; }


