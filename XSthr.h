/*
  Doesn't call destructor upon thread exit.
 */

#ifndef USE_THREADS

#define dTHRINIT(PREFIX, constructor, destructor)		\
static PREFIX##_thr *PREFIX##_single = 0;			\
static void *PREFIX##_newthr()			\
{ PREFIX##_single = (PREFIX##_thr*) constructor(); return PREFIX##_single; } \
extern int errno

#define THRINFO(PREFIX, var) \
var = ((PREFIX##_thr *)(PREFIX##_single ? PREFIX##_single : PREFIX##_newthr()))

#else

#define dTHRINIT(PREFIX, constructor, destructor)		\
static int PREFIX##_key = -1;					\
static PREFIX##_thr *PREFIX##_newthr()				\
{								\
  SV *isv;							\
  PREFIX##_thr *info;						\
  if (PREFIX##_key == -1) {					\
    int items;							\
    dSP;							\
    PUSHMARK(SP);						\
    XPUSHs(sv_2mortal(newSVpv("Thread::Specific", 16)));	\
    PUTBACK;							\
    items = perl_call_method("key_create", G_SCALAR);		\
    assert(items==1);						\
    SPAGAIN;							\
    PREFIX##_key = POPi(SP);					\
    PUTBACK;							\
  }								\
  assert(thr->specific);					\
  isv = *av_fetch(thr->specific, PREFIX##_key, 1);		\
  info = constructor();						\
  sv_setiv(isv, (IV) info);					\
  SvREFCNT_inc(isv);						\
  return info;							\
} \
extern int errno

#define THRINFO(PREFIX, var)						\
STMT_START {								\
  SV **_info = av_fetch(thr->specific, FatTree_key, 0);			\
  var = (PREFIX##_thr *) (_info? SvIV(*_info) : PREFIX##_newthr());	\
} STMT_END

#endif
