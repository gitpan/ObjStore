// -*-c++-*- is in the bag.
#include "osperl.hh"

/*--------------------------------------------- registration */

struct BEGIN_setarray {
  BEGIN_setarray();
  static void *mk(os_segment *seg, char *name, os_unsigned_int32 card);
};
BEGIN_setarray::BEGIN_setarray()
{ osperl::register_spec("ObjStore::Set::Array", mk); }

void *BEGIN_setarray::mk(os_segment *seg, char *name, os_unsigned_int32 card)
{
  if (card > 10000) {
    card = 10000;
    warn("setarray: cardinality cannot be greater than 10000");
  }
  return new(seg, OSPV_setarray::get_os_typespec()) OSPV_setarray(card);
}

static BEGIN_setarray run_setarray;

/*--------------------------------------------- setarray */

OSPV_setarray::OSPV_setarray(int size)
  : cv(size,8)
{
  //  warn("new OSPV_setarray(%d)", size);
}

OSPV_setarray::~OSPV_setarray()
{
#ifdef DEBUG_MEM_OSSVPV
  warn("~OSPV_setarray %x", this);
#endif
  CLEAR();
}

char *OSPV_setarray::base_class()
{ return "ObjStore::Set"; }

int OSPV_setarray::first(int start)
{
  int xx;
  for (xx=start; xx < cv.count(); xx++) {
    if (cv[xx].natural() != ossv_undef) return xx;
  }
  return -1;
}

double OSPV_setarray::cardinality()
{
  int good=0;
  for (int xx=0; xx < cv.count(); xx++) {
    if (cv[xx].natural() != ossv_undef) good++;
  }
  return good;
}

double OSPV_setarray::percent_unused()
{
  if (cv.size_allocated() <= 0) return 0;
  return (cv.size_allocated() - cardinality()) / (double) cv.size_allocated();
}

SV *OSPV_setarray::ADD(SV *nval)
{
  int spot=-1;
  // stupid, but definitely correct
  for (int xx=0; xx < cv.count(); xx++) {
    if (cv[xx].natural() != ossv_undef) continue;
    spot = xx;
    break;
  }
  if (spot == -1) spot = cv.count();
  cv[spot] = nval;
  if (cv[spot].natural() != ossv_obj)
    croak("OSPV_setarray::ADD(nval): sets can only contain objects");

  //  warn("added %s", cv[spot].as_pv());
  /*
  for (int zz=0; zz < cv.count(); zz++) {
    warn("cv[%d]: %d\n", zz, cv[zz].natural());
  }
  */
  if (GIMME_V == G_VOID) return 0;
  return osperl::ossv_2sv(&cv[spot]);
}

int OSPV_setarray::CONTAINS(SV *val)
{
  OSSVPV *pv = 0;
  ossv_magic *mg = osperl::sv_2magic(val);
  if (mg) pv = mg->ospv();
  if (!pv) croak("OSPV_setarray::CONTAINS(SV *val): must be persistent object");

  for (int xx=0; xx < cv.count(); xx++) {
    if (cv[xx] == pv) return 1;
  }
  return 0;
}

void OSPV_setarray::REMOVE(SV *nval)
{
  OSSVPV *pv = 0;
  ossv_magic *mg = osperl::sv_2magic(nval);
  if (mg) pv = mg->ospv();
  if (!pv) croak("OSPV_setarray::REMOVE(SV *val): must be persistent object");

  // stupid, but definitely correct
  for (int xx=0; xx < cv.count(); xx++) {
    if (cv[xx] == pv) {
      cv[xx].set_undef();
      return;
    }
  }
}

struct setarray_magic : ossv_magic {
  int cursor;
  setarray_magic(OSSV *, OSSVPV *);
};
setarray_magic::setarray_magic(OSSV *_sv, OSSVPV *_pv) : ossv_magic(_sv,_pv), cursor(0)
{}

ossv_magic *OSPV_setarray::NEW_MAGIC(OSSV *sv, OSSVPV *pv)
{ return new setarray_magic(sv,pv); }

SV *OSPV_setarray::FIRST(ossv_magic *vmg)
{
  setarray_magic *mg = (setarray_magic *) vmg;
  assert(mg);
  /*
  for (int xx=0; xx < cv.count(); xx++) {
    warn("cv[%d]: %d\n", xx, cv[xx].natural());
  }
  */
  mg->cursor=first(0);
  //  warn("FIRST: cursor = %d", mg->cursor);
  if (mg->cursor != -1) {
    return osperl::ospv_2sv((OSSVPV*) cv[mg->cursor].vptr);
  } else {
    return &sv_undef;
  }
}

SV *OSPV_setarray::NEXT(ossv_magic *vmg)
{
  setarray_magic *mg = (setarray_magic *) vmg;
  assert(mg);
  mg->cursor++;
  mg->cursor = first(mg->cursor);
  //  warn("NEXT: cursor = %d", mg->cursor);
  if (mg->cursor != -1) {
    return osperl::ospv_2sv((OSSVPV*) cv[mg->cursor].vptr);
  } else {
    return &sv_undef;
  }
}

void OSPV_setarray::CLEAR()
{
  for (int xx=0; xx < cv.count(); xx++) { cv[xx].set_undef(); }
}

/*--------------------------------------------- registration */

struct BEGIN_sethash {
  BEGIN_sethash();
  static void *mk(os_segment *seg, char *name, os_unsigned_int32 card);
};
BEGIN_sethash::BEGIN_sethash()
{ osperl::register_spec("ObjStore::Set::Hash", mk); }

void *BEGIN_sethash::mk(os_segment *seg, char *name, os_unsigned_int32 card)
{ return new(seg, OSPV_sethash::get_os_typespec()) OSPV_sethash(card); }

static BEGIN_sethash run_sethash;

/*--------------------------------------------- sethash */

OSPV_sethash::OSPV_sethash(os_unsigned_int32 size)
  : set(size)
{
  //  warn("new OSPV_sethash(%d)", size);
}

OSPV_sethash::~OSPV_sethash()
{
#ifdef DEBUG_MEM_OSSVPV
  warn("~OSPV_sethash %x", this);
#endif
  CLEAR();
}

char *OSPV_sethash::base_class()
{ return "ObjStore::Set"; }

double OSPV_sethash::cardinality()
{ return set.cardinality(); }

double OSPV_sethash::percent_unused()
{ return .30; }  //???

SV *OSPV_sethash::ADD(SV *nval)
{
  OSSVPV *ospv=0;

  ossv_magic *mg = osperl::sv_2magic(nval);
  if (mg) {
    ospv = mg->ospv();
    if (ospv) ospv->REF_inc();
  }

  if (!ospv) {
    ENTER ;
    SAVETMPS ;
    ossv_magic *mg = osperl::force_sv_2magic(os_segment::of(this), nval);
    ospv = mg->ospv();
    if (!ospv) croak("OSPV_sethash::ADD(SV*): cannot add non-object");
    ospv->REF_inc();
    FREETMPS ;
    LEAVE ;
  }

  set.insert(ospv);
  if (GIMME_V == G_VOID) return 0;
  return osperl::ospv_2sv(ospv);
}

int OSPV_sethash::CONTAINS(SV *nval)
{
  OSSVPV *ospv=0;
  ossv_magic *mg = osperl::sv_2magic(nval);
  if (mg) ospv = mg->ospv();
  if (!ospv) croak("OSPV_sethash::CONTAINS(SV *nval): cannot test non-object");
  return set.contains(ospv);
}

void OSPV_sethash::REMOVE(SV *nval)
{
  OSSVPV *ospv=0;
  ossv_magic *mg = osperl::sv_2magic(nval);
  if (mg) ospv = mg->ospv();
  if (!ospv) croak("OSPV_sethash::REMOVE(SV *nval): cannot remove non-object");
  if (set.remove(ospv)) ospv->REF_dec();
}

struct sethash_magic : ossv_magic {
  os_cursor *cs;
  sethash_magic(OSSV *, OSSVPV *);
};
sethash_magic::sethash_magic(OSSV *_sv, OSSVPV *_pv) : ossv_magic(_sv,_pv), cs(0)
{}

ossv_magic *OSPV_sethash::NEW_MAGIC(OSSV *sv, OSSVPV *pv)
{ return new sethash_magic(sv,pv); }

SV *OSPV_sethash::FIRST(ossv_magic *vmg)
{
  sethash_magic *mg = (sethash_magic *) vmg;
  assert(mg);
  if (!mg->cs) mg->cs = new os_cursor(set);
  return osperl::ospv_2sv( (OSSVPV*) mg->cs->first());
}

SV *OSPV_sethash::NEXT(ossv_magic *vmg)
{
  sethash_magic *mg = (sethash_magic *) vmg;
  assert(mg);
  assert(mg->cursor);
  return osperl::ospv_2sv( (OSSVPV*) mg->cs->next());
}

void OSPV_sethash::CLEAR()
{
  while (!set.empty()) {
    OSSVPV *pv = (OSSVPV*) set.pick();
    set.remove(pv);
    pv->REF_dec();
  }
}

