/*
Copyright (c) 1997 Joshua Nathaniel Pritikin.  All rights reserved.
This package is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.
*/

#include <assert.h>
#include <string.h>
#include "osperl.hh"

//#define DEBUG_OSSV_VALUES
//#define DEBUG_MEM_OSSVPV
//#define DEBUG_NEW_OSSV
//#define DEBUG_REFCNT
//#define DEBUG_HVDICT

/*--------------------------------------------- typemap services */

static SV *inline_tied(SV *rv)		// snapped from pp_sys.c 5.004
{
    if (! SvROK(rv)) return 0;
    SV *sv = SvRV(rv);
    MAGIC * mg ;
    if (SvMAGICAL(sv)) {
        if (SvTYPE(sv) == SVt_PVHV || SvTYPE(sv) == SVt_PVAV)
            mg = mg_find(sv, 'P') ;
        else
            mg = mg_find(sv, 'q') ;

        if (mg)  {
            return mg->mg_obj;
	}
    }
    return 0;
}

// how does this stuff work?!
static void warn_tie_magic(SV *var)
{
  MAGIC * mg ;

  warn("exploring tie magic 0x%x", var);

  if (SvROK(var)) {
    warn("deref");
    var = SvRV(var);
  }

  warn("SvTYPE(var) = %d", SvTYPE(var));
  if (SvTYPE(var) == SVt_PVHV || SvTYPE(var) == SVt_PVAV) {
    warn("AV or HV");
    mg = mg_find(var, 'P');
    if (mg) warn("tied!");
  } else {
    warn("SV");
    mg = mg_find(var, 'q');
    if (mg) warn("tied SV!");
  }
}

static OSSV *sv_2ossv(SV *nval)
{
  SV *_tmp_ossv = inline_tied( nval );
  if (_tmp_ossv) {
    if (sv_isobject(_tmp_ossv) && (SvTYPE(SvRV(_tmp_ossv)) == SVt_PVMG)) {
      return (OSSV *) SvIV((SV*)SvRV( _tmp_ossv ));
    }
  } else if (sv_isobject( nval ) && (SvTYPE(SvRV( nval )) == SVt_PVMG) ) {
    return (OSSV *) SvIV((SV*)SvRV( nval ));
  }
  return 0;
}

static SV *ossv_2sv(OSSV *ossv)
{
  if (!ossv) return &sv_undef;
  switch (ossv->natural()) {
  case ossv_undef: return &sv_undef;
  case ossv_iv:    return newSViv(ossv->u.iv);
  case ossv_nv:    return newSVnv(ossv->u.nv);
  case ossv_pv:    return newSVpv((char*) ossv->u.pv.vptr, ossv->u.pv.len);
  case ossv_hv:
  case ossv_av:{
    char *CLASS = (ossv->natural() == ossv_hv? "ObjStore::HV":"ObjStore::AV");
    SV *_tied = sv_setref_pv(sv_newmortal(), CLASS, (void*)ossv);
    SV *_tmpsv;
    if (ossv->natural() == ossv_hv) _tmpsv = sv_2mortal((SV*)newHV());
    else _tmpsv = sv_2mortal((SV*)newAV());
    sv_magic(_tmpsv, _tied, 'P', Nullch, 0);

    SV *rv = newRV(_tmpsv);
    --SvREFCNT(SvRV(rv));
    char *clname = ((OSSVPV*)ossv->u.pv.vptr)->classname;
    if (clname) {
	HV* stash = gv_stashpv(clname, TRUE);
	(void)sv_bless(rv, stash);
    }
    return rv;
  }
  case ossv_cv:{
    char *CLASS = ((OSSVPV*)ossv->u.pv.vptr)->classname;
    if (!CLASS) CLASS = "ObjStore::CV";
    return sv_setref_pv(sv_newmortal(), CLASS, (void*)ossv);
  }
  default:
    warn("OSSV %s is not implemented", ossv->Type());
    return &sv_undef;
  }
}

static SV *hkey_2sv(hkey *hk)
{
  if (!hk) return &sv_undef;
  return sv_2mortal(newSVpv(hk->as_pv(), 0));
}

/*--------------------------------------------- OSSV */

// assume _refs=1, i.e. allocated inside an array

OSSV::OSSV()
{ _refs=1; _type = ossv_undef; }

OSSV::OSSV(SV *nval)
{ _refs=1; _type = ossv_undef; this->operator=(nval); }

OSSV::OSSV(OSSV *nval)
{ _refs=1; *this = *nval; }

OSSV::~OSSV()
{ undef(); }

// references and roots can REFER
// hashes and arrays (OSSVPV) can BE REFERRED TO

void OSSV::REF_inc()
{
 _refs++;
#ifdef DEBUG_REFCNT
  warn("OSSV::REF_inc() 0x%x to %d", this, _refs);
#endif
}

void OSSV::REF_dec()
{
  _refs--;
#ifdef DEBUG_REFCNT
  warn("OSSV::REF_dec() 0x%x to %d", this, _refs);
#endif
  REF_chk();
}

void OSSV::REF_chk()
{
  if (_refs <= 0) {
#ifdef DEBUG_REFCNT
    warn("OSSV::REF_chk() =%d deleting 0x%x", _refs, this);
#endif
    delete this;
  }
}

int OSSV::PvREFok()
{
  switch (natural()) {
  case ossv_av:
  case ossv_hv:
  case ossv_cv:
    return 1;
  default:
    return 0;
  }
}

void OSSV::PvREF_inc(void *nval)
{
  if (PvREFok()) {
    if (nval) u.pv.vptr = nval;
    assert(u.pv.vptr != 0);
    ((OSSVPV*)u.pv.vptr)->REF_inc();
  }
}

void OSSV::PvREF_dec()
{
  if (PvREFok()) { ((OSSVPV*)u.pv.vptr)->REF_dec(); u.pv.vptr = 0; }
}

OSSV *OSSV::operator=(SV *nval)
{
  OSSV *ossv = sv_2ossv(nval);
  if (ossv) {
    this->s(ossv);
    return this;
  }

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
  if (SvIOKp(nval)) {
    s((os_int32) SvIV(nval));
  } else if (SvNOKp(nval)) {
    s(SvNV(nval));
  } else if (SvPOKp(nval)) {
    tmp = SvPV(nval, tmplen);   //memory leak? XXX
    s(tmp, tmplen);
  } else if (! SvOK(nval)) {
    undef();
  } else {
    warn("OSSV::operator =(SV*) - not yet");
  }
  return this;
}

OSSV *OSSV::operator =(const OSSV &nval)
{ s(&nval); return this; }

int OSSV::operator==(const OSSV &nval)
{
  if (natural() != nval.natural()) return 0;
  switch (natural()) {
    case ossv_undef: return 1;
    case ossv_iv:    return u.iv == nval.u.iv;
    case ossv_nv:    return u.nv == nval.u.nv;
    case ossv_pv:    return (u.pv.len == nval.u.pv.len &&
			     strcmp((char*)u.pv.vptr, (char*)nval.u.pv.vptr)==0);
    case ossv_rv:    croak("not implemented");
    case ossv_av: case ossv_hv: case ossv_cv:
      return u.pv.vptr == nval.u.pv.vptr;
    default:         die("negligent developer");
  };
}

ossvtype OSSV::natural() const
{ return (ossvtype) _type; }

os_int32 OSSV::discriminant()
{
  // XXX handle byte swapping for mixed architectures
  switch (natural()) {
    case ossv_undef: return 0;
    case ossv_iv:    return 1;
    case ossv_nv:    return 2;
    case ossv_pv:    return 3;
    case ossv_rv:    return 0;
    case ossv_av:    return 3;
    case ossv_hv:    return 3;
    case ossv_cv:    return 3;
    default:         die("negligent developer");
  }
}

// prepare to switch to new datatype
int OSSV::morph(ossvtype nty)
{
  if (_type == nty) return 0;

  if ((nty == ossv_av || nty == ossv_hv || nty == ossv_cv) &&
      _type != ossv_undef) {
    croak("Can't coerce %s to ref type", Type());
  }

  PvREF_dec();
  switch (_type) {
  case ossv_undef: case ossv_iv: case ossv_nv:
    break;

  case ossv_pv:
#ifdef DEBUG_OSSV_VALUES
    warn("OSSV::morph(%d -> %d): deleting string '%s' 0x%x", _type, nty,u.pv.vptr,u.pv.vptr);
#endif
    delete [] ((char*)u.pv.vptr);
    u.pv.vptr = 0;
    break;

  case ossv_rv:
  case ossv_av: case ossv_hv: case ossv_cv: break;

  default: croak("OSSV::morph type %s unknown", Type());
  }
  _type = nty;
  return 1;
}

void OSSV::undef()
{ morph(ossv_undef); }

void OSSV::s(os_int32 nval)
{
  morph(ossv_iv); u.iv = nval;
#ifdef DEBUG_OSSV_VALUES
  warn("OSSV(0x%x) = iv(%d)", this, nval);
#endif
}

void OSSV::s(double nval)
{
  morph(ossv_nv); u.nv = nval;
#ifdef DEBUG_OSSV_VALUES
  warn("OSSV(0x%x) = nv(%f)", this, nval);
#endif
}

// nlen is length of string including null terminator
void OSSV::s(char *nval, os_unsigned_int32 nlen)  // simple copy implementation
{
//  warn("OSSV::s - prior type = %d", _type);
  if (!morph(ossv_pv)) {
#ifdef DEBUG_OSSV_VALUES
    warn("OSSV::s(%s, %d): deleting string 0x%x", nval, nlen, u.pv.vptr);
#endif
    delete [] ((char*)u.pv.vptr);   // probably wrong length
    u.pv.vptr = 0;
  }
  u.pv.len = nlen;
  char *str = new(os_segment::of(this), os_typespec::get_char(), u.pv.len) char[u.pv.len];
#ifdef DEBUG_OSSV_VALUES
  warn("OSSV::s(%s, %d): alloc string 0x%x", nval, nlen, str);
#endif
  memcpy(str, nval, u.pv.len);
  u.pv.vptr = str;
}

void OSSV::s(const OSSV *nval)
{ 
  switch (nval->natural()) {

   // value semantics
  case ossv_undef: undef(); break;
  case ossv_iv: s(nval->u.iv); break;
  case ossv_nv: s(nval->u.nv); break;
  case ossv_pv: s((char*) nval->u.pv.vptr, nval->u.pv.len); break;
    
  case ossv_rv:			// alien data
    morph(nval->natural());
    croak("not yet");
    break;
    
  case ossv_av: case ossv_hv: case ossv_cv:   // ref counted semantics
    if (morph(nval->natural())) {
      PvREF_inc(nval->u.pv.vptr);
    } else if (u.pv.vptr != nval->u.pv.vptr) {
      PvREF_dec();
      PvREF_inc(nval->u.pv.vptr);
    }
    break;
  }
}

void OSSV::new_array(char *rep)
{
  morph(ossv_av);
  croak("arrays not implemented yet");
  PvREF_inc();
}

void OSSV::new_hash(char *rep)
{
  morph(ossv_hv);
  if (strcmp(rep, "array")==0) {
    u.pv.vptr = new(os_segment::of(this), OSPV_hvarray::get_os_typespec()) OSPV_hvarray;
#ifdef DEBUG_MEM_OSSVPV
    warn("OSSV::new_hash(): new OSPV_hvarray = 0x%x", u.pv.vptr);
#endif
  } else if (strcmp(rep, "dict")==0) {
    u.pv.vptr = new(os_segment::of(this), OSPV_hvdict::get_os_typespec()) OSPV_hvdict;
#ifdef DEBUG_MEM_OSSVPV
    warn("OSSV::new_hash(): new OSPV_hvdict = 0x%x", u.pv.vptr);
#endif
  } else {
    croak("new_hash(%s): unknown representation", rep);
  }
  PvREF_inc();
}

void OSSV::new_sack(char *rep)
{
  morph(ossv_cv);
  if (strcmp(rep, "array")==0) {
    u.pv.vptr = new(os_segment::of(this), OSPV_cvarray::get_os_typespec()) OSPV_cvarray;
#ifdef DEBUG_MEM_OSSVPV
    warn("OSSV::new_sack(): new OSPV_cvarray = 0x%x", u.pv.vptr);
#endif
  } else {
    croak("OSSV::new_sack(%s): unknown representation", rep);
  }
  PvREF_inc();
}

char *OSSV::Type()  // similar to Ref
{
  switch (natural()) {
   case ossv_undef: return "undef";
   case ossv_iv:    return "int";
   case ossv_nv:    return "double";
   case ossv_pv:    return "string";
   case ossv_rv:    return "REF";
   case ossv_av:    return "ARRAY";
   case ossv_hv:    return "HASH";
   case ossv_cv:    return "SACK";
   default: croak("unknown type");
  }
};

os_segment *OSSV::get_segment()
{ return os_segment::of(PvREFok()? u.pv.vptr : this); }

os_int32 OSSV::as_iv()
{
  switch (natural()) {
    case ossv_iv: return u.iv;
    case ossv_nv: return (I32) u.nv;
    default:
      warn("SV %s has no int representation", Type());
      return 0;
  }
}

double OSSV::as_nv()
{
  switch (natural()) {
    case ossv_iv: return u.iv;
    case ossv_nv: return u.nv;
    default:
      warn("SV %s has no double representation", Type());
      return 0;
  }
}

char OSSV::strrep[32];  // temporary space for string representation

char *OSSV::as_pv()     // returned string does not need to be freed
{
  switch (natural()) {
    case ossv_iv:   sprintf(strrep, "%ld", u.iv); break;
    case ossv_nv:   sprintf(strrep, "%f", u.nv); break;
    case ossv_pv:   return (char*) u.pv.vptr;
    case ossv_rv: case ossv_av: case ossv_hv: case ossv_cv:
      sprintf(strrep, "%s(0x%lx)", Type(), u.pv.vptr);
      break;
    default:
      warn("SV %s has no string representation", Type());
      strrep[0]=0;
      break;
  }
  return strrep;
}

os_unsigned_int32 OSSV::as_pvn()
{
  if (natural() == ossv_pv) {
    return u.pv.len;
  } else {
    warn("SV %s has no string length", Type());
    return 0;
  }
}

/*--------------------------------------------- hkey */
// A hkey is smaller than a pointer to a string!
// hkey assumes no strings with embedded nulls - problem? XXX

char hkey::strrep[HKEY_MAXLEN+2];  // temporary space for string representation

hkey::hkey()
{ undef(); }

hkey::hkey(const hkey &k1)
{ memcpy(str, k1.str, HKEY_MAXLEN); }

hkey::hkey(const char *s1)
{
  if (strlen(s1) > HKEY_MAXLEN)
    warn("hkey must be less than %d chars: '%s' truncated", HKEY_MAXLEN, s1);
  strncpy(str, s1, HKEY_MAXLEN);
}

void hkey::undef()
{ str[0] = 0; }

int hkey::valid()
{ return str[0] != 0; }

hkey *hkey::operator=(const hkey &k1)
{ memcpy(this->str, k1.str, HKEY_MAXLEN); return this; }

hkey *hkey::operator=(char *k1)
{ hkey tmp(k1); *this = tmp; return this; }

os_unsigned_int32 hkey::hash(const void *v1)
{
  const hkey *s1 = (hkey*)v1;
  return *((os_unsigned_int32*) s1->str);
}

char *hkey::as_pv()
{
  memset(strrep, 0, HKEY_MAXLEN+2);
  memcpy(strrep, str, HKEY_MAXLEN);
  return strrep;
}

// just use memcmp? XXX
int hkey::rank(const void *v1, const void *v2)
{
  const hkey *s1 = (hkey*)v1;
  const hkey *s2 = (hkey*)v2;
  const unsigned long h1 = *((unsigned long*) s1->str);
  const unsigned long h2 = *((unsigned long*) s2->str);
  if (h1 == h2) {
    return strncmp(s1->str, s2->str, HKEY_MAXLEN);
  } else {
    if (h1 > h2) return os_collection::GT;
    else return os_collection::LT;
  }
}

hent *hent::operator=(const hent &nval)
{
  hk.operator=(nval.hk); hv.operator=(nval.hv);
  return this;
}

/*--------------------------------------------- OSSVPV */

OSSVPV::OSSVPV()
  : _refs(0), classname(0)
{}
OSSVPV::~OSSVPV()
{ set_classname(0); }

void OSSVPV::set_classname(char *nval)
{
  if (classname) delete [] classname;
  classname=0;
  if (nval) {
    int len = strlen(nval)+1;
    classname = new(os_segment::of(this), os_typespec::get_char(), len) char[len];
    strcpy(classname, nval);
  }
}

void OSSVPV::REF_inc() {
  _refs++;
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

/*--------------------------------------------- OSPV_ templates */

SV *OSSVPV::FETCHi(int) { croak("OSSVPV::FETCH"); return 0; }
SV *OSSVPV::STOREi(int, SV *) { croak("OSSVPV::STORE"); return 0; }
SV *OSSVPV::FETCHp(char *) { croak("OSSVPV::FETCH"); return 0; }
SV *OSSVPV::STOREp(char *, SV *) { croak("OSSVPV::STORE"); return 0; }
void OSSVPV::DELETE(char *) { croak("OSSVPV::DELETE"); }
void OSSVPV::CLEAR() { croak("OSSVPV::CLEAR"); }
int OSSVPV::EXISTS(char *) { croak("OSSVPV::EXISTS"); return 0; }
SV *OSSVPV::FIRSTKEY() { croak("OSSVPV::FIRSTKEY"); return 0; }
SV *OSSVPV::NEXTKEY(char *) { croak("OSSVPV::NEXTKEY"); return 0; }
void OSSVPV::ADD(SV *) { croak("OSSVPV::ADD"); }
void OSSVPV::REMOVE(SV *) { croak("OSSVPV::REMOVE"); }
SV *OSSVPV::FIRST() { croak("OSSVPV::FIRST"); return 0; }
SV *OSSVPV::NEXT() { croak("OSSVPV::NEXT"); return 0; }

/*--------------------------------------------- OSPV_cvarray */

OSPV_cvarray::OSPV_cvarray()
  : cursor(0), cv(7,8)
{}

OSPV_cvarray::~OSPV_cvarray()
{
#ifdef DEBUG_MEM_OSSVPV
  warn("~OSPV_cvarray %x", this);
#endif
  CLEAR();
}

int OSPV_cvarray::first(int start)
{
  int xx;
  for (xx=start; xx < cv.count(); xx++) {
    if (cv[xx].natural() != ossv_undef) return xx;
  }
  return -1;
}

void OSPV_cvarray::ADD(SV *nval)
{
  OSSV *ossv = sv_2ossv(nval);
  if (!ossv) { croak("OSPV_cvarray::ADD(SV *nval): cannot store non-OSSV"); }
  
  // stupid, but definitely correct
  for (int xx=0; xx < cv.count(); xx++) {
    if (cv[xx].natural() != ossv_undef) continue;
    cv[xx].s(ossv);
    return;
  }
  cv[cv.count()].s(ossv);
}

void OSPV_cvarray::REMOVE(SV *nval)
{
  OSSV *ossv = sv_2ossv(nval);
  if (!ossv) { croak("OSPV_cvarray::REMOVE(SV *nval): cannot remove non-OSSV"); }

  // stupid, but definitely correct
  for (int xx=0; xx < cv.count(); xx++) {
    if (cv[xx] == *ossv) {
      cv[xx].undef();
      return;
    }
  }
}

SV *OSPV_cvarray::FIRST()
{
//  for (int xx=0; xx < cv.count(); xx++) {
//    warn("cv[%d]: %d\n", xx, cv[xx].natural());
//  }

  cursor=first(0);
  if (cursor != -1) {
    return ossv_2sv(&cv[cursor]);
  } else {
    return &sv_undef;
  }
}

SV *OSPV_cvarray::NEXT()
{
  cursor++;
  cursor = first(cursor);
  if (cursor != -1) {
    return ossv_2sv(&cv[cursor]);
  } else {
    return &sv_undef;
  }
}

void OSPV_cvarray::CLEAR()
{
  for (int xx=0; xx < cv.count(); xx++) { cv[xx].undef(); }
}

/*--------------------------------------------- OSPV_hvarray */

OSPV_hvarray::OSPV_hvarray()
  : cursor(0), hv(7,8)
{}

OSPV_hvarray::~OSPV_hvarray()
{
#ifdef DEBUG_MEM_OSSVPV
  warn("~OSPV_hvarray %x", this);
#endif
  CLEAR();
}

int OSPV_hvarray::index_of(char *key)
{
  hkey look(key);
  int ok=0;
  for (int xx=0; xx < hv.count(); xx++) {
    if (hkey::rank(&hv[xx].hk, &look) == 0) return xx;
  }
  return -1;
}

SV *OSPV_hvarray::FETCHp(char *key)
{
  int xx = index_of(key);
  if (xx == -1) {
    return &sv_undef;
  } else {
    return ossv_2sv(&hv[xx].hv);
  }
}

SV *OSPV_hvarray::STOREp(char *key, SV *value)
{
  int xx = index_of(key);
  if (xx == -1) {
    xx = hv.count();
    hv[hv.count()].hk = key;
  }
  hv[xx].hv = value;
  return ossv_2sv(&hv[xx].hv);  // may become invalid if array grows... XXX
}

void OSPV_hvarray::DELETE(char *key)
{
  int xx = index_of(key);
  if (xx != -1) {
    hv[xx].hk.undef();
    hv[xx].hv.undef();
  }
}

void OSPV_hvarray::CLEAR()
{
  cursor = 0;
  while ((cursor = first(cursor)) != -1) {
    hv[cursor].hk.undef();
    hv[cursor].hv.undef();
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

SV *OSPV_hvarray::FIRSTKEY()
{
  SV *out;
  cursor = first(0);
  if (cursor != -1) {
    out = hkey_2sv(&hv[cursor].hk);
  } else {
    out = &sv_undef;
  }
  return out;
}

SV *OSPV_hvarray::NEXTKEY(char *lastkey)
{
  SV *out;
  cursor++;
  cursor = first(cursor);
  if (cursor != -1) {
    out = hkey_2sv(&hv[cursor].hk);
  } else {
    out = &sv_undef;
  }
  return out;
}

/*--------------------------------------------- OSPV_hvdict */

OSPV_hvdict::OSPV_hvdict()
  : hv(107,
       os_dictionary::signal_dup_keys |
       os_collection::pick_from_empty_returns_null |
       os_dictionary::dont_maintain_cardinality),
    cs(hv)
{}

OSPV_hvdict::~OSPV_hvdict()
{
#ifdef DEBUG_MEM_OSSVPV
  warn("~OSPV_hvdict %x", this);
#endif
  CLEAR();
}

SV *OSPV_hvdict::FETCHp(char *key)
{
  OSSV *ret = hv.pick(key);
#ifdef DEBUG_HVDICT
  warn("OSPV_hvdict::FETCH %s => %s", key, ret? ret->as_pv() : "<0x0>");
#endif
  return ossv_2sv(ret);
}

SV *OSPV_hvdict::STOREp(char *key, SV *nval)
{
  os_segment *WHERE = os_segment::of(this);
  OSSV *ossv=0;
  int insert=0;

  if (!ossv) {
    ossv = (OSSV*) hv.pick(key);
    if (ossv) *ossv = nval;
  }
  if (!ossv) {
    insert=1;
    ossv = sv_2ossv(nval);
    if (ossv) ossv->REF_inc();
  }
  if (!ossv) {
    ossv = new(WHERE, OSSV::get_os_typespec()) OSSV;
#ifdef DEBUG_NEW_OSSV
    warn("OSPV_hvdict::STOREp(%s, SV *nval, SV **out): new OSSV = 0x%x", key, ossv);
#endif
    *ossv = nval;
  }
  assert(ossv);
#ifdef DEBUG_HVDICT
  warn("OSPV_hvdict::INSERT(%s=%s)", key, ossv->as_pv());
#endif
  if (insert) hv.insert(key, ossv);

  return ossv_2sv(ossv);
}

void OSPV_hvdict::DELETE(char *key)
{
  OSSV *val = hv.pick(key);
  hv.remove_value(key);
#ifdef DEBUG_HVDICT
  warn("OSPV_hvdict::DELETE(%s) deleting hash value 0x%x", key, val);
#endif
  if (val) val->REF_dec();   //XXX val==0 ?
}

void OSPV_hvdict::CLEAR()
{
  while (cs.first()) {
    hkey *k1 = (hkey*) hv.retrieve_key(cs);
    OSSV *val = hv.pick(k1);
    hv.remove_value(*k1);
#ifdef DEBUG_HVDICT
    warn("OSPV_hvdict::CLEAR() deleting hash value 0x%x", val);
#endif
    if (val) val->REF_dec();
  }
}

int OSPV_hvdict::EXISTS(char *key)
{
  int out = hv.pick(key) != 0;
#ifdef DEBUG_HVDICT
  warn("OSPV_hvdict::exists %s => %d", key, out);
#endif
  return out;
}

SV *OSPV_hvdict::FIRSTKEY()
{
  hkey *k1=0;
  if (cs.first()) {
    k1 = (hkey*) hv.retrieve_key(cs);
    assert(k1);
  }
#ifdef DEBUG_HVDICT
  warn("OSPV_hvdict::FIRSTKEY => %s", k1? k1->as_pv() : "undef");
#endif
  return hkey_2sv(k1);
}

SV *OSPV_hvdict::NEXTKEY(char *lastkey)
{
  hkey *k1=0;
  if (cs.next()) {
    k1 = (hkey*) hv.retrieve_key(cs);
    assert(k1);
  }
#ifdef DEBUG_HVDICT
  warn("OSPV_hvdict::NEXTKEY => %s", k1? k1->as_pv() : "undef");
#endif
  return hkey_2sv(k1);
}

//----------------------------- Constants

static os_fetch_policy str_2fetch(char *str)
{
  if (strcmp(str, "segment")==0) return os_fetch_segment;
  if (strcmp(str, "page")==0) return os_fetch_page;
  if (strcmp(str, "stream")==0) return os_fetch_stream;
  croak("str_2fetch: %s unrecognized", str);
}

static void osperl_exception_hook(tix_exception_p cause, os_int32 value,
	os_char_p report)
{
  warn("ObjectStore: %s", report);
  perl_eval_pv("&Carp::confess", TRUE);
  exit(1);
}

static void setup_exception_hook()
{ tix_exception::set_unhandled_exception_hook(osperl_exception_hook); }

//----------------------------- ObjStore

MODULE = ObjStore	PACKAGE = ObjStore

BOOT:
  objectstore::initialize();		// should delay boot for flexibility XXX
  objectstore::set_thread_locking(0);
  os_collection::set_thread_locking(0);
  os_index_key(hkey, hkey::rank, hkey::hash);
  setup_exception_hook();

static char *
ObjStore::schema_dir()
	CODE:
	RETVAL = SCHEMADIR;
	OUTPUT:
	RETVAL

static void
ObjStore::begin_update()
	CODE:
	os_transaction::begin(os_transaction::update);

static void
ObjStore::begin_read()
	CODE:
	os_transaction::begin(os_transaction::read_only);

static void
ObjStore::begin_abort()
	CODE:
	os_transaction::begin(os_transaction::abort_only);

static int
ObjStore::in_transaction()
	CODE:
	RETVAL = os_transaction::get_current() != 0;
	OUTPUT:
	RETVAL

static void
ObjStore::commit()
	CODE:
	os_transaction::commit();

static void
ObjStore::abort()
	CODE:
	os_transaction::abort();

static void
ObjStore::STATS()
	CODE:
	printf("sizeof(os_int16) = %d; sizeof(os_int32) = %d\n", sizeof(os_int16), sizeof(os_int32));
	printf("sizeof(OSSV::ossv_value) = %d; sizeof(double) = %d\n", sizeof(OSSV::ossv_value), sizeof(double));
	printf("sizeof(OSSV) = %d; sizeof(hkey) = %d\n", sizeof(OSSV), sizeof(hkey));

#-----------------------------# Database

MODULE = ObjStore	PACKAGE = ObjStore::Database

static os_database *
os_database::open(pathname, read_only, create_mode)
	char *pathname
	int read_only
	int create_mode

void
os_database::close()

void
os_database::destroy()

void
os_database::decache()

int
os_database::get_default_segment_size()

int
os_database::get_sector_size()

time_t
os_database::time_created()

int
os_database::is_open()

void
os_database::open_mvcc()

int
os_database::is_open_mvcc()

int
os_database::is_open_read_only()

int
os_database::is_writable()

void
os_database::set_fetch_policy(policy, ...)
	char *policy;
	PROTOTYPE: $;$
	CODE:
	int bytes=4096;
	if (items == 2) bytes = SvIV(ST(1));
	THIS->set_fetch_policy(str_2fetch(policy), bytes);

os_segment *
os_database::get_segment(num)
	int num
	CODE:
	char *CLASS = "ObjStore::Segment";
	RETVAL = THIS->get_segment(num);
	OUTPUT:
	RETVAL

void
os_database::get_all_segments()
	PPCODE:
	char *CLASS = "ObjStore::Segment";
	os_int32 num = THIS->get_n_segments();
	os_segment **segs = new os_segment*[num];
	THIS->get_all_segments(num, segs, num);
	EXTEND(sp, num);
	int xx;
	for (xx=0; xx < num; xx++) {
		PUSHs(sv_setref_pv( newSViv(0) , CLASS, segs[xx] ));
	}

OSSV *
os_database::newHV(rep)
	char *rep
	CODE:
	char *CLASS = "ObjStore::HV";
	os_segment *arena = THIS->get_default_segment();
	OSSV *ossv = new(arena, OSSV::get_os_typespec()) OSSV;
	ossv->_refs=0;
#ifdef DEBUG_NEW_OSSV
	warn("os_database::newHV(%s): OSSV = 0x%x", rep, ossv);
#endif
	ossv->new_hash(rep);
	RETVAL = ossv;
	OUTPUT:
	RETVAL

SV *
os_database::newSack(rep)
	char *rep
	CODE:
	os_segment *arena = THIS->get_default_segment();
	OSSV *ossv = new(arena, OSSV::get_os_typespec()) OSSV;
	ossv->_refs=0;
#ifdef DEBUG_NEW_OSSV
	warn("os_database::newSack(%s): OSSV = 0x%x", rep, ossv);
#endif
	ossv->new_sack(rep);
	ST(0) = ossv_2sv(ossv);

#-----------------------------# Root

MODULE = ObjStore	PACKAGE = ObjStore::Database

os_database_root *
os_database::create_root(name)
	char *name
	PREINIT:
	char *CLASS = "ObjStore::Root";

os_database_root *
os_database::find_root(name)
	char *name
	PREINIT:
	char *CLASS = "ObjStore::Root";

MODULE = ObjStore	PACKAGE = ObjStore::Root

void
os_database_root::destroy()
	CODE:
	OSSV *ossv = (OSSV*) THIS->get_value();  // check type! XXX
	if (ossv) ossv->REF_dec();
	delete THIS;

SV *
os_database_root::get_value()
	CODE:
	if (!THIS) XSRETURN_UNDEF;
	OSSV *ossv = (OSSV*) THIS->get_value();  // check type! XXX
	ST(0) = ossv_2sv(ossv);

void
os_database_root::set_value(sv)
	SV *sv
	CODE:
	OSSV *ossv = sv_2ossv(sv);
	if (!ossv) croak("os_database_root::set_value(sv): bad type");
	if (!THIS) croak("ObjStore::ROOT->set_value(nval)");
	OSSV *prior = (OSSV*) THIS->get_value();
	if (prior) {		// check type! XXX
	  prior->REF_dec();
	}
	THIS->set_value(ossv, OSSV::get_os_typespec());
	ossv->REF_inc();

#-----------------------------# Transaction (?)

MODULE = ObjStore	PACKAGE = ObjStore::Transaction

static os_transaction *
os_transaction::get_current()

#-----------------------------# Segment

MODULE = ObjStore	PACKAGE = ObjStore::Database

os_segment *
os_database::create_segment()
	PREINIT:
	char *CLASS = "ObjStore::Segment";

MODULE = ObjStore	PACKAGE = ObjStore::Segment

void
os_segment::destroy()
	CODE:
	if (!THIS->is_empty()) croak("attempt to destroy unempty os_segment");
	THIS->destroy();

int
os_segment::size()

int
os_segment::get_number()

void
os_segment::set_comment(info)
	char *info
	CODE:
	char short_info[32];
	strncpy(short_info, info, 31);
	short_info[31] = 0;
	THIS->set_comment(short_info);

char *
os_segment::get_comment()

void
os_segment::set_fetch_policy(policy, ...)
	char *policy;
	PROTOTYPE: $;$
	CODE:
	int bytes=4096;
	if (items == 2) bytes = SvIV(ST(1));
	THIS->set_fetch_policy(str_2fetch(policy), bytes);

static os_segment *
os_segment::of(sv)
	SV *sv
	CODE:
	OSSV *ossv = sv_2ossv(sv);
	if (!ossv) croak("os_segment::of(ossv): must be persistent object");
	RETVAL = ossv->get_segment();
	OUTPUT:
	RETVAL

OSSV *
os_segment::newHV(rep)
	char *rep
	CODE:
	char *CLASS = "ObjStore::HV";
	OSSV *ossv = new(THIS, OSSV::get_os_typespec()) OSSV;
	ossv->_refs=0;
#ifdef DEBUG_NEW_OSSV
	warn("os_segment::newHV(%s): OSSV = 0x%x", rep, ossv);
#endif
	ossv->new_hash(rep);
	RETVAL = ossv;
	OUTPUT:
	RETVAL

SV *
os_segment::newSack(rep)
	char *rep
	CODE:
	OSSV *ossv = new(THIS, OSSV::get_os_typespec()) OSSV;
	ossv->_refs=0;
#ifdef DEBUG_NEW_OSSV
	warn("os_segment::newSack(%s): OSSV = 0x%x", rep, ossv);
#endif
	ossv->new_sack(rep);
	ST(0) = ossv_2sv(ossv);

#-----------------------------# HV

MODULE = ObjStore	PACKAGE = ObjStore::HV

char *
OSSV::Type()

void
OSSV::DESTROY()
	CODE:
	if (!THIS) croak("THIS invalid");
	THIS->REF_chk();

SV *
OSSV::FETCH(key)
	char *key;
	CODE:
	if (!THIS) croak("THIS invalid");
	if (THIS->natural() != ossv_hv) croak("THIS=%s is not a HASH", THIS->Type());
	OSSVPV *hv = (OSSVPV *) THIS->u.pv.vptr;
	assert(hv);
	ST(0) = hv->FETCHp(key);

SV *
OSSV::_STORE(key, nval)
	char *key;
	SV *nval;
	CODE:
	if (!THIS) croak("THIS invalid");
	if (THIS->natural() != ossv_hv) croak("THIS=%s is not a HASH", THIS->Type());
	OSSVPV *hv = (OSSVPV *) THIS->u.pv.vptr;
	assert(hv);
	ST(0) = hv->STOREp(key, nval);

void
OSSV::DELETE(key)
	char *key;
	CODE:
	if (!THIS) croak("THIS invalid");
	if (THIS->natural() != ossv_hv) croak("THIS=%s is not a HASH", THIS->Type());
	OSSVPV *hv = (OSSVPV *) THIS->u.pv.vptr;
	assert(hv);
	hv->DELETE(key);

int
OSSV::EXISTS(key)
	char *key;
	CODE:
	if (!THIS) croak("THIS invalid");
	if (THIS->natural() != ossv_hv) croak("THIS=%s is not a HASH", THIS->Type());
	OSSVPV *hv = (OSSVPV *) THIS->u.pv.vptr;
	assert(hv);
	RETVAL = hv->EXISTS(key);
	OUTPUT:
	RETVAL

SV *
OSSV::FIRSTKEY()
	CODE:
	if (!THIS) croak("THIS invalid");
	if (THIS->natural() != ossv_hv) croak("THIS=%s is not a HASH", THIS->Type());
	OSSVPV *hv = (OSSVPV *) THIS->u.pv.vptr;
	assert(hv);
	ST(0) = hv->FIRSTKEY();

SV *
OSSV::NEXTKEY(lastkey)
	char *lastkey;
	CODE:
	if (!THIS) croak("THIS invalid");
	if (THIS->natural() != ossv_hv) croak("THIS=%s is not a HASH", THIS->Type());
	OSSVPV *hv = (OSSVPV *) THIS->u.pv.vptr;
	assert(hv);
	ST(0) = hv->NEXTKEY(lastkey);

void
OSSV::CLEAR()
	CODE:
	if (!THIS) croak("THIS invalid");
	if (THIS->natural() != ossv_hv) croak("THIS=%s is not a HASH", THIS->Type());
	OSSVPV *hv = (OSSVPV *) THIS->u.pv.vptr;
	assert(hv);
	hv->CLEAR();

#-----------------------------# CV

MODULE = ObjStore	PACKAGE = ObjStore::CV

char *
OSSV::Type()

void
OSSV::DESTROY()
	CODE:
	if (!THIS) croak("THIS invalid");
	THIS->REF_chk();

void
OSSV::a(nval)
	SV *nval;
	CODE:
	if (!THIS) croak("THIS invalid");
	if (THIS->natural() != ossv_cv) croak("THIS=%s is not a SACK", THIS->Type());
	OSSVPV *cv = (OSSVPV *) THIS->u.pv.vptr;
	assert(cv);
	cv->ADD(nval);

void
OSSV::r(nval)
	SV *nval;
	CODE:
	if (!THIS) croak("THIS invalid");
	if (THIS->natural() != ossv_cv) croak("THIS=%s is not a SACK", THIS->Type());
	OSSVPV *cv = (OSSVPV *) THIS->u.pv.vptr;
	assert(cv);
	cv->REMOVE(nval);

SV *
OSSV::first()
	CODE:
	if (!THIS) croak("THIS invalid");
	if (THIS->natural() != ossv_cv) croak("THIS=%s is not a SACK", THIS->Type());
	OSSVPV *cv = (OSSVPV *) THIS->u.pv.vptr;
	assert(cv);
	ST(0) = cv->FIRST();

SV *
OSSV::next()
	CODE:
	if (!THIS) croak("THIS invalid");
	if (THIS->natural() != ossv_cv) croak("THIS=%s is not a SACK", THIS->Type());
	OSSVPV *cv = (OSSVPV *) THIS->u.pv.vptr;
	assert(cv);
	ST(0) = cv->NEXT();

