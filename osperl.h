/*Copyright © 1997-1998 Joshua Nathaniel Pritikin.  All rights reserved.*/

#ifndef __osperl_h__
#define __osperl_h__

#undef rs
#include <ostore/ostore.hh>
#include <ostore/osreleas.hh>

#undef croak
#define croak osp_croak
extern void osp_croak(const char* pat, ...);

// Merge perl and ObjectStore typedefs!
// It is better to be precise about fields widths in a database,
// therefore OS types are preferred.
#undef I32
#define I32 os_int32
#undef U32
#define U32 os_unsigned_int32
#undef I16
#define I16 os_int16
#undef U16
#define U16 os_unsigned_int16

// OSSV has only 16 bits to store type information.  Yikes!

// NOTE: It probably would have been slightly more efficient to make
// 0=UNDEF instead of 1=UNDEF.  At the time I felt the extra checking
// was worth it.

#define OSVt_UNDEF2		0
#define OSVt_UNDEF		1
#define OSVt_IV32		2
#define OSVt_NV			3
#define OSVt_PV			4	// char string
#define OSVt_RV			5
#define OSVt_IV16		6
//#define OSVt_IV64??		7
//#define OSVt_1CHAR		8
//#define OSVt_2CHAR		9

#define OSVTYPEMASK		0x07
#define OSvTYPE(sv)		((sv)->_type & OSVTYPEMASK)
#define OSvTYPE_set(sv,to) \
	(sv)->_type = (((sv)->_type & ~OSVTYPEMASK) | (to & OSVTYPEMASK))

// ROSHARE is undo-able until the ROCNT reach 2^16 - 10
#define OSVf_ROEXCL		0x40
#define OSVf_ROSHARE		0x80
#define OSvFLAG_set(sv,flag,on)			\
STMT_START {					\
	if (on) ((sv)->_type |= (flag));	\
	else ((sv)->_type &= ~(flag));		\
} STMT_END
#define OSvROSHARE_set(sv,on)	OSvFLAG_set(sv,OSVf_ROSHARE,on)
#define OSvROEXCL(sv)		((sv)->_type & OSVf_ROEXCL)
#define OSvROCLEAR(sv)		OSvFLAG_set(sv, OSVf_ROEXCL|OSVf_ROSHARE, 0)
#define OSvREADONLY(sv)		((sv)->_type & (OSVf_ROEXCL|OSVf_ROSHARE))

#define OSvTRYWRITE(sv)						\
STMT_START {							\
  if (OSvREADONLY(sv))			\
    croak("ObjStore: attempt to modify READONLY %s='%s'",	\
	  sv->type_2pv(), sv->stringify());			\
} STMT_END

struct ospv_bridge;
struct OSSVPV;
struct OSPV_Generic;

// 8 bytes
struct OSSV {
  static os_typespec *get_os_typespec();
  static char strrep1[64];
  static char strrep2[64];
  void *vptr;
  os_int16 xiv;
  os_int16 _type;

  //init
  OSSV();
  OSSV(SV *);
  OSSV(OSSVPV *);
  ~OSSV();
  OSSV *operator=(int);  //help C++ templates call undef (?) XXX
  OSSV *operator=(SV *);
  OSSV *operator=(OSSV &);
  OSSV *operator=(const OSSV &);
  int operator==(OSSVPV *pv);
  //what
  int morph(int nty);
  int natural() const;
  int is_set();
  int istrue();
  int compare(OSSV*);
  static void verify_correct_compare();
  char *type_2pv();
  static char *type_2pv(int);
  OSSVPV *get_ospv();
  OSPV_Generic *ary();
  //refcnt
  int PvREFok();
  void PvREF_inc(void *foo);
  void PvREF_dec();
  //set
  void FORCEUNDEF();
  void set_undef();
  void s(os_int32);
  void s(double);
  void s(char *, os_unsigned_int32 len);
  void s(OSSV *);
  void s(OSSVPV *);
  void s(ospv_bridge *mg);
  //get
  char *stringify(char *tmp = 0);
};

#define OSvIV32(sv)	((OSPV_iv*)(sv)->vptr)->iv
#define OSvNV(sv)	((OSPV_nv*)(sv)->vptr)->nv
#define OSvRV(sv)	((OSSVPV*)(sv)->vptr)
#define OSvPV(sv,len)	(len = (sv)->xiv, (char*)(sv)->vptr)
#define OSvIV16(sv)	(sv)->xiv

struct OSPV_iv {
  static os_typespec *get_os_typespec();
  os_int32 iv;
};

struct OSPV_nv {
  static os_typespec *get_os_typespec();
  double nv;
};

#define OSPV_INUSE	0x0001	/* protect against race conditions */
#define OSPV_BLESS2	0x0002	/* blessed with 'bless version 2' */
#define OSPV_REPLOCK	0x0004	/* do not change representation dynamically XXX */

#define OSPvFLAGS(pv)		(pv)->pad_1
#define OSPvROCNT(pv)		(pv)->_weak_refs

#define OSPvINUSE(pv)		(OSPvFLAGS(pv) & OSPV_INUSE)
#define OSPvINUSE_on(pv)	(OSPvFLAGS(pv) |= OSPV_INUSE)
#define OSPvINUSE_off(pv)	(OSPvFLAGS(pv) &= ~OSPV_INUSE)
#define OSPvBLESS2(pv)		(OSPvFLAGS(pv) & OSPV_BLESS2)
#define OSPvBLESS2_on(pv)	(OSPvFLAGS(pv) |= OSPV_BLESS2)
#define OSPvBLESS2_off(pv)	(OSPvFLAGS(pv) &= ~OSPV_BLESS2)

struct OSSVPV : os_virtual_behavior {
  static os_typespec *get_os_typespec();
  os_unsigned_int32 _refs;
  os_unsigned_int16 _weak_refs;	//rename to 'readonly'
  os_int16 pad_1;		//rename to 'flags'
  char *classname;		//should be an OSSVPV*
  OSSVPV();
  virtual ~OSSVPV();
  void REF_inc();
  void REF_dec();
  void ROCNT_inc();
  void ROCNT_dec();
  int _is_blessed();
  int can_update(void *vptr);
  void NOTFOUND(char *meth);
  void fwd2rep(char *methname, SV **top, int items);
  HV *get_stash();

  virtual void bless(SV *);
  virtual char *os_class(STRLEN *len);  //must be NULL terminated too
  virtual char *rep_class(STRLEN *len);
  virtual int get_perl_type();
  // you must implement none or both of the following:
  virtual OSSV *traverse(char *keyish);
  virtual OSSVPV *traverse2(char *keyish);
  virtual void ROSHARE_set(int on);
  // C++ cast hacks
  virtual int is_OSPV_Ref2();
};

struct OSPVptr {
  static os_typespec *get_os_typespec();
  OSSVPV *rv;
  OSPVptr() :rv(0) {}
  ~OSPVptr() { set_undef(); }
  void set_undef() { if (rv) { rv->REF_dec(); rv=0; } }
  void operator=(OSSVPV *npv) { set_undef(); rv=npv; rv->REF_inc(); }
  operator OSSVPV*() { return rv; }
  OSSVPV *resolve() { return rv; }
  void steal(OSPVptr &nval) { set_undef(); rv = nval.rv; nval.rv=0; }

  // DANGER // DANGER // DANGER //
  void FORCEUNDEF() { /*REF_dec*/ rv=0; }
  OSSVPV *detach() { OSSVPV *ret = rv; /*REF_dec*/ rv=0; return ret; }
  void attach(OSSVPV *nval) { set_undef(); rv = nval; /*REF_inc*/ }
};

struct OSPV_Ref2 : OSSVPV {
  static os_typespec *get_os_typespec();
  OSPV_Ref2();
  virtual char *os_class(STRLEN *len);
  virtual os_database *get_database();
  virtual int deleted();
  virtual OSSVPV *focus();
  virtual char *dump();
  virtual int is_OSPV_Ref2();
};

struct OSPV_Ref2_hard : OSPV_Ref2 {
  static os_typespec *get_os_typespec();
  os_reference myfocus;
  OSPV_Ref2_hard(OSSVPV *);
  OSPV_Ref2_hard(char *, os_database *);
  virtual os_database *get_database();
  virtual int deleted();
  virtual OSSVPV *focus();
  virtual char *dump();
};

struct OSPV_Ref2_protect : OSPV_Ref2 {
  static os_typespec *get_os_typespec();
  os_reference_protected myfocus;
  OSPV_Ref2_protect(OSSVPV *);
  OSPV_Ref2_protect(char *, os_database *);
  virtual os_database *get_database();
  virtual int deleted();
  virtual OSSVPV *focus();
  virtual char *dump();
};

struct OSPV_Cursor; //XXX

// A cursor must be a single composite object.  Otherwise you
// need cursors for cursors!

struct OSPV_Cursor2 : OSSVPV {
  static os_typespec *get_os_typespec();
  virtual char *os_class(STRLEN *len);
//  virtual os_database *get_database();   //only for cross-database
//  virtual int deleted();
  virtual OSSVPV *focus();
  virtual char *rep_class(STRLEN *len);
  virtual void moveto(I32);
  virtual void step(I32 delta);
  virtual void keys();		// index might have multiple keys
  virtual void at();		// value stored
  virtual void store(SV *);
  virtual int seek(SV **, int items);
  virtual void ins(SV *, int left);     // push=0/unshift=1
  virtual void del(SV *, int left);     // pop=0/shift=1
  virtual I32 pos();
  virtual void stats();
};

// Any OSSVPV that contains pointers to other OSSVPVs (except a cursor)
// must be a container.  Also note that the STORE method must be compatible
// with the cursor output (when reasonable).

struct OSPV_Container : OSSVPV {
  static os_typespec *get_os_typespec();
  virtual double _percent_filled();
  virtual int FETCHSIZE();
  virtual void CLEAR();
  virtual OSSVPV *new_cursor(os_segment *seg);
};

// simple hash slot -- use it or write your own
struct hvent2 {
  static os_typespec *get_os_typespec();
  char *hk;
  OSSV hv;
  hvent2();
  ~hvent2();
  void FORCEUNDEF();
  void set_undef();
  int valid() const;
  void set_key(char *nkey);
//  hvent2 *operator=(int zero);
  int rank(const char *v2);
  SV *key_2sv();
};

// Methods should accept SV* and return OSSV*, OSPV_*, or void 
// (avoid SV* !).  'void' is preferred and the most flexible. 
// Not all methods conform to this convention yet.

// Generic collections support the standard perl array & hash
// collection types.  This is 1 class (instead of 2-3) because you might
// have a single collection that can be accessed as a hash or
// an index or an array.  (And there is no down-side except C++ ugliness,
// and you already have that anyway. :-)

struct OSPV_Generic : OSPV_Container {
  static os_typespec *get_os_typespec();
  virtual OSSV *FETCH(SV *key);
  virtual OSSV *STORE(SV *key, SV *value);
  // hash
  virtual OSSV *hvx(char *key);
  virtual void DELETE(char *key);
  virtual int EXISTS(char *key);
  virtual SV *FIRST(ospv_bridge*);
  virtual SV *NEXT(ospv_bridge*);
  // array
  virtual OSSV *avx(int xx);
  virtual void POP();
  virtual void SHIFT();
  virtual void PUSH(SV **base, int items);
  virtual void UNSHIFT(SV **base, int items);
  virtual void SPLICE(int offset, int length, SV **top, int count);
  // index
  virtual int add(OSSVPV *);
  virtual char *remove(OSSVPV *);
  virtual void configure(SV **top, int items);
  virtual OSSVPV *FETCHx(SV *keyish);
  static OSSV *path_2key(OSSVPV *obj, OSPV_Generic *path);
};

#define INDEX_MAXKEYS 8

struct osp_pathref {
  int descending;
  int keycnt;
  OSPV_Generic *pcache[INDEX_MAXKEYS];
  OSSV *keys[INDEX_MAXKEYS];
  osp_pathref();
  void init(OSSVPV *paths);
  void init(OSSVPV *paths, OSSVPV *target);
  void set_descending(int descend);
  int compare(OSSVPV *);
  int compare(OSSVPV *d1, OSSVPV *d2);
};

struct osp_pathexam : osp_pathref {
  OSSVPV *trail[INDEX_MAXKEYS*4]; //XXX
  int failed;
  int trailcnt;
  int is_excl;
  int excl_ok;
  int is_transient;
  char mode;
  osp_pathexam(OSPV_Generic *paths, OSSVPV *target, char mode, int excl,
	       int in_transient);
  void abort();
  void commit();
};

////////////////////////////////////////////////////////////////////////
// DEPRECIATED (but still included for schema compatibility)

struct OSPV_Ref : OSSVPV {
  static os_typespec *get_os_typespec();
  OSPV_Ref(OSSVPV *);
  OSPV_Ref(char *, os_database *);
  virtual ~OSPV_Ref();
  virtual char *os_class(STRLEN *len);
  os_reference_protected myfocus;
  os_database *get_database();
  char *dump();
  int deleted();
  OSSVPV *focus();
};

struct OSPV_Cursor : OSPV_Ref {
  static os_typespec *get_os_typespec();
  OSPV_Cursor(OSSVPV *);
  virtual char *os_class(STRLEN *len);
  virtual void seek_pole(int);
  virtual void at();
  virtual void next();
};

#if !OSSG
/*
  Safety, then Speed;  There are lots of interlocking refcnts:

  - Each bridge has a refcnt to the SV that holds it's transaction.

  - Each transaction has a linked ring of bridges.

  - Each bridge has a refcnt to the persistent object, but only
    during updates (and in writable databases).
 */

struct osp_txn;
struct osp_bridge_link {
  osp_bridge_link *next, *prev;
};
struct osp_bridge : osp_bridge_link {
  int refs;
  int detached;
  int manual_hold;
  int holding;  //true if changed REFCNT
  SV *txsv;				// my transaction scope

#ifdef OSP_DEBUG  
  int br_debug;
#define BrDEBUG(b) b->br_debug
#define BrDEBUG_set(b,to) BrDEBUG(b)=to
#define DEBUG_bridge(br,a)   if (BrDEBUG(br) || osp_thr::fetch()->debug & 4) a
#else
#define BrDEBUG(b) 0
#define BrDEBUG_set(b,to)
#define DEBUG_bridge(br,a)
#endif

  void init();
  osp_txn *get_transaction();
  void leave_perl();
  void enter_txn(osp_txn *txn);
  void leave_txn();
  int invalid();
  virtual void freelist();
  virtual ~osp_bridge();
  virtual void unref();
  virtual void hold();
  virtual int is_weak();
};

// ODI seemed to want to restrict tix_handlers to lexical scope.  We trump
// them:
struct dytix_handler {
  tix_handler hand;
  dytix_handler();
};

#ifdef DEBUG_ALLOCATION

#define NEW_OS_OBJECT(ret, near, typespec, type)	\
STMT_START {						\
  osp_thr::record_new(0,"before", #type);			\
  ret = new(near, typespec) type;			\
  osp_thr::record_new(ret,"after", #type);			\
} STMT_END


#define NEW_OS_ARRAY(ret, near, typespec, type, width)	\
STMT_START {						\
  osp_thr::record_new(0, "before", #type, width);		\
  ret = new(near, typespec, width) type[width];		\
  osp_thr::record_new(ret, "after", #type, width);		\
} STMT_END

#else

#define NEW_OS_OBJECT(ret, near, typespec, type)	\
  ret = new(near, typespec) type

#define NEW_OS_ARRAY(ret, near, typespec, type, width)	\
  ret = new(near, typespec, width) type[width]

#endif


// per-thread globals
struct osp_thr {
  osp_thr();
  ~osp_thr();

  //global globals
  static void boot();
  static osp_thr *fetch();
  static SV *stargate;
  static HV *CLASSLOAD;
  static SV *TXGV;
  static AV *TXStack;

  //methods
  static void record_new(void *vptr, char *when, char *type, int ary=0);

  //context
  long signature;
  long debug;
  SV *errsv;
  dytix_handler *hand;
  char *report;

  //glue methods
  ospv_bridge *ospv_freelist;
  static os_segment *sv_2segment(SV *);
  static ospv_bridge *sv_2bridge(SV *, int force, os_segment *near=0);
  static SV *ossv_2sv(OSSV *ossv, int hold=0);
  static SV *ospv_2sv(OSSVPV *, int hold=0);
  static SV *wrap(OSSVPV *ospv, SV *br);

  OSSV *plant_sv(os_segment *, SV *);
  OSSV *plant_ospv(os_segment *seg, OSSVPV *pv);
  void push_ospv(OSSVPV *pv);
};

struct osp_txn {
  osp_txn(os_transaction::transaction_type_enum,
	  os_transaction::transaction_scope_enum);
  int is_aborted();
  void abort();
  void commit();
  void pop();
//  void burn_bridge();
  void checkpoint();
  void post_transaction();
  int can_update(os_database *);
  int can_update(void *);
  void prepare_to_commit();
  int is_prepare_to_commit_invoked();
  int is_prepare_to_commit_completed();

  os_transaction::transaction_type_enum tt;
  os_transaction::transaction_scope_enum ts;
  os_transaction *os;
  U32 owner;   //for local transactions; not yet XXX
  osp_bridge_link ring;
};

#define dOSP osp_thr *osp = osp_thr::fetch()
#define dTXN							\
mysv_lock(osp_thr::TXGV);					\
osp_txn *txn = 0;						\
if (AvFILL(osp_thr::TXStack) >= 0) {				\
  SV *_txsv = SvRV(*av_fetch(osp_thr::TXStack,			\
			    AvFILL(osp_thr::TXStack), 0));	\
  txn = (osp_txn*) SvIV(_txsv);					\
}


// THESE MACROS CAN PROBABLY BE REMOVED NOW
//
// 1. REMOVE THEM
// 2. RE-TEST
// 3. GRIN

#define OSP_START0				\
STMT_START {					\
int odi_cxx_ok=0;				\
TIX_HANDLE(all_exceptions)

#define OSP_ALWAYS0 \
odi_cxx_ok=1;							\
TIX_EXCEPTION							\
  sv_setpv(osp->errsv, tix_local_handler.get_report());		\
TIX_END_HANDLE							\

#define OSP_END0						\
if (!odi_cxx_ok) croak("ObjectStore: %s", SvPV(osp->errsv, na));\
} STMT_END;

#define OSP_ALWAYSEND0 OSP_ALWAYS0 OSP_END0

struct osp_smart_object {
  virtual void REF_inc();
  virtual void REF_dec();
  virtual ~osp_smart_object();
};

// do not use as a super-class!!
struct ospv_bridge : osp_bridge {
  OSSVPV *pv;
  osp_smart_object *info;

  virtual void init(OSSVPV *_pv);
  virtual void unref();
  virtual void hold();
  virtual int is_weak();
  virtual void freelist();
  OSSVPV *ospv();
};

#ifdef OSPERL_PRIVATE
#define OSP_INIT(z) z
#else
#define OSP_INIT(z)
#endif

// Safe, easy, embedded, fixed maximum length strings
// Can you tell that I hate templates?
#define DECLARE_FIXEDSTRING(W)				\
struct FixedStr ## W {					\
  static os_typespec *get_os_typespec();		\
  static int maxlen;					\
  os_unsigned_int8 len;					\
  char ch[ W ];						\
  void set(char *pv, STRLEN pvn) {			\
    len = (pvn > maxlen)? maxlen : pvn;			\
    memcpy(ch, pv, len);				\
  }							\
  void operator=(char *pv) { set(pv,strlen(pv)); }	\
  void operator=(SV *sv) {				\
    STRLEN tmp;						\
    char *pv = SvPV(sv, tmp);				\
    set(pv,tmp);					\
  }							\
  SV *svcopy() { return newSVpvn(ch, len); }		\
};							\
OSP_INIT(int FixedStr##W::maxlen = W;)

// Conservative alignment dictates sizeof a multiple of 4 bytes.
//
// Anything longer than 35 characters can probably afford
// real allocation overhead.
//
DECLARE_FIXEDSTRING(3)
DECLARE_FIXEDSTRING(7)
DECLARE_FIXEDSTRING(11)
DECLARE_FIXEDSTRING(15)
DECLARE_FIXEDSTRING(19)
DECLARE_FIXEDSTRING(23)
DECLARE_FIXEDSTRING(27)
DECLARE_FIXEDSTRING(31)
DECLARE_FIXEDSTRING(35)
#undef DECLARE_FIXSTRING

#endif

// These are temporary and might disappear!
extern "C" void mysv_dump(SV *sv);
extern "C" void mysv_lock(SV *sv);

#endif
