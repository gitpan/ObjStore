//                                                              -*-C++-*-
// Copyright � 1997-1998 Joshua Nathaniel Pritikin.  All rights reserved.

#ifndef __osperl_h__
#define __osperl_h__

#undef rs
#include <ostore/ostore.hh>
#include <ostore/osreleas.hh>
#include <ostore/nreloc/schftyps.hh>

// croak thru Carp!
#undef croak
#define croak osp_croak
extern void osp_croak(const char* pat, ...);

// Merge perl and ObjectStore typedefs!
// It is better to be precise about fields widths in a database,
// therefore OS types are preferred.  Perl type widths are less
// stringently enforced.

#undef I32
#define I32 os_int32
#undef U32
#define U32 os_unsigned_int32
#undef I16
#define I16 os_int16
#undef U16
#define U16 os_unsigned_int16

#define OSPERL_API_VERSION 2

// OSSV has only 16 bits to store type information.  Yikes!

// NOTE: It probably would have been slightly more efficient to make
// 0=UNDEF instead of 1=UNDEF from the beginning.  At the time I felt
// the extra checking was worth it.  Since that time I have become
// very confident that databases are not being corrupted.
//
// Since the vptr of undef must be zero, we can reuse UNDEF2
// for IV64 later, without fear.

#define OSVt_UNDEF		0
#define OSVt_UNDEF2		1	// old undef (VERSION < 1.41)
//#define OSVt_IV64??		
#define OSVt_IV32		2
#define OSVt_NV			3
#define OSVt_PV			4	// char string
#define OSVt_RV			5
#define OSVt_IV16		6
#define OSVt_1CHAR		7
// also store os_reference(_this_DB) directly?

#define OSVTYPEMASK		0x07	// use 0x0f ??
#define OSvTYPE(sv)		((sv)->_type & OSVTYPEMASK)
#define OSvTYPE_set(sv,to) \
	(sv)->_type = (((sv)->_type & ~OSVTYPEMASK) | (to & OSVTYPEMASK))

#define OSvIV32(sv)	((OSPV_iv*)(sv)->vptr)->iv
#define OSvNV(sv)	((OSPV_nv*)(sv)->vptr)->nv
#define OSvRV(sv)	((OSSVPV*)(sv)->vptr)
#define OSvPV(sv,len)	(OSvTYPE(sv)==OSVt_PV?			\
			 (len = (sv)->xiv, (char*)(sv)->vptr) :	\
			 (len = 1, (char*)&(sv)->xiv))
#define OSvIV16(sv)	(sv)->xiv

//#define OSVf_TEMP		0x20 ??
#define OSVf_INDEXED		0x40
#define OSVf_READONLY		0x80

#define OSvREADONLY(sv)		((sv)->_type & OSVf_READONLY)
#define OSvREADONLY_on(sv)	((sv)->_type |= OSVf_READONLY)

#define OSvINDEXED(sv)		((sv)->_type & OSVf_INDEXED)
#define OSvINDEXED_on(sv)	((sv)->_type |= OSVf_INDEXED)
#define OSvINDEXED_off(sv)	((sv)->_type &= ~OSVf_INDEXED)

struct ospv_bridge;
struct OSSVPV;
struct OSPV_Generic;
class osp_pathexam;
struct osp_smart_object;

// 8 bytes
struct OSSV {
  static os_typespec *get_os_typespec();
  static char strrep1[64];
  static char strrep2[64];
  void *vptr;
  os_int16 xiv;
  os_int16 _type;

  // inline methods? XXX
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
  int folded_typeof() const;
  int is_set();
  int istrue();
  int compare(OSSV*);
  static void verify_correct_compare();
  char *type_2pv();
  static char *type_2pv(int);
  OSSVPV *as_rv();
  OSSVPV *safe_rv();
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

struct OSPV_iv {
  static os_typespec *get_os_typespec();
  os_int32 iv;
};

struct OSPV_nv {
  static os_typespec *get_os_typespec();
  double nv;
};

/* All sub-types are required to provide at least 1 byte worth of flags */

#define OSPV_INUSE	0x0001	/* protect against race conditions */
#define OSPV_BLESS2	0x0002	/* blessed with 'bless version 2' */
#define OSPV_DELETED	0x0004	/* this object will be deleted soon */
#define OSPV_REPLOCK	0x0008	/* ?do not change representation dynamically XXX */
#define OSPV_MODCNT	0x0010	/* ?increment the modcnt for every modification */
#define OSPV_pFLAGS	0xFF00	/* private flags for sub-classes */

#define OSPvFLAGS(pv)		(pv)->pad_1

#define OSPvINUSE(pv)		(OSPvFLAGS(pv) & OSPV_INUSE)
#define OSPvINUSE_on(pv)	(OSPvFLAGS(pv) |= OSPV_INUSE)
#define OSPvINUSE_off(pv)	(OSPvFLAGS(pv) &= ~OSPV_INUSE)

#define OSPvBLESS2(pv)		(OSPvFLAGS(pv) & OSPV_BLESS2)
#define OSPvBLESS2_on(pv)	(OSPvFLAGS(pv) |= OSPV_BLESS2)
#define OSPvBLESS2_off(pv)	(OSPvFLAGS(pv) &= ~OSPV_BLESS2)

#define OSPvDELETED(pv)		(OSPvFLAGS(pv) & OSPV_DELETED)
#define OSPvDELETED_on(pv)	(OSPvFLAGS(pv) |= OSPV_DELETED)

typedef void *(*dynacast_fn)(void *obj, HV *stash);

struct OSSVPV : os_virtual_behavior {
  os_unsigned_int32 _refs;
  // _weak_refs unused (1.42) - schema evolution hell!  Drat!
  os_unsigned_int16 _weak_refs;
  os_int16 pad_1;		//rename to 'flags'
  char *classname;		//should be OSPVptr, alas...
  OSSVPV();
  virtual ~OSSVPV();
  void REF_inc();
  void REF_dec();
  int _is_blessed();
  int can_update(void *vptr);
  void NOTFOUND(char *meth);
  void fwd2rep(char *methname, SV **top, int items);
  void bless(SV *);
  HV *get_stash();
  HV *load_stash_cache(char *CLASS, STRLEN CLEN, OSPV_Generic *blessinfo);

  virtual int get_perl_type();
  virtual dynacast_fn get_dynacast_meth();
  virtual void make_constant();
  virtual void _debug1(void *); //whatever you want

  // must be NULL terminated
  virtual char *os_class(STRLEN *len);
  virtual char *rep_class(STRLEN *len);

  // C++ cast hacks
  virtual int is_OSPV_Ref2();
  virtual int is_OSPV_Generic();

  //--------- should be under OSPV_Container but casting is tiresome -||
  virtual void POSH_CD(SV *to);
  virtual int FETCHSIZE();

  // osp_pathexam support (containers only!)
  virtual OSSVPV *traverse1(osp_pathexam &exam);
  virtual OSSV *traverse2(osp_pathexam &exam);

  // OSPV_Generic: internal index configuration, etc
  virtual OSSV *avx(int xx);
  virtual OSSV *hvx(char *key);
  //--------- should be under OSPV_Container but casting is tiresome -||
};


// It's too bad this isn't used everywhere to hold OSSVPV*.
// I only thought of it recently, after the schema was frozen.

class OSPVptr {
private:
  OSSVPV *rv;
public:
  static os_typespec *get_os_typespec();
  OSPVptr() :rv(0) {}
  ~OSPVptr() { set_undef(); }
  void set_undef() { if (rv) { rv->REF_dec(); rv=0; } }
  void operator=(OSSVPV *npv)
    { OSSVPV *old = rv; rv=npv; if (rv) rv->REF_inc(); if (old) old->REF_dec(); }
  operator OSSVPV*() { return rv; }
  OSSVPV *resolve() { return rv; }
  void steal(OSPVptr &nval) { set_undef(); rv = nval.rv; nval.rv=0; }

  // DANGER // DANGER // DANGER //
  void FORCEUNDEF() { /*REF_dec*/ rv=0; }
  OSSVPV *detach() { OSSVPV *ret = rv; /*REF_dec*/ rv=0; return ret; }
  void attach(OSSVPV *nval) { set_undef(); rv = nval; /*REF_inc*/ }
};

struct OSPV_Ref2 : OSSVPV {
  OSPV_Ref2();
  virtual char *os_class(STRLEN *len);
  virtual os_database *get_database();
  virtual int deleted();
  virtual OSSVPV *focus();
  virtual char *dump();
  virtual int is_OSPV_Ref2();
};

// A cursor must be a single composite object.  Otherwise you
// need cursors for cursors!

struct OSPV_Cursor2 : OSSVPV {
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
  virtual int seek(osp_pathexam &);
  virtual void ins(SV *, int left);     // push=0/unshift=1
  virtual void del(SV *, int left);     // pop=0/shift=1
  virtual I32 pos();
  virtual void stats();
};

// Any OSSVPV that contains pointers to other OSSVPVs (except a cursor)
// must be a container.  Also note that the STORE method must be compatible
// with the cursor output (when reasonable).

struct OSPV_Container : OSSVPV {
  virtual void CLEAR();
  virtual OSSVPV *new_cursor(os_segment *seg);
  virtual double _percent_filled();    //EXPERIMENTAL
};

// Methods should accept SV* and return OSSV*, OSPV_*, or void 
// (avoid SV* !).  'void' is preferred and the most flexible. 
// Everything is subject to change to match the perltie interface.

// Generic collections support the standard perl array & hash
// collection types.  This is 1 class (instead of 2-3) because you might
// have a single collection that can be accessed as a hash or
// an index or an array.  (And there is no down-side except C++ ugliness,
// and you already have that anyway. :-)

struct OSPV_Generic : OSPV_Container {
  virtual int is_OSPV_Generic();
  virtual void FETCH(SV *key);
  virtual void POSH_CD(SV *to);    // defaults to FETCH; or override
  virtual void STORE(SV *key, SV *value);
  // hash
  virtual void DELETE(SV *key);
  virtual int EXISTS(SV *key);
  virtual void FIRST(osp_smart_object **);
  virtual void NEXT(osp_smart_object **);
  // array
  virtual void POP();
  virtual void SHIFT();
  virtual void PUSH(SV **base, int items);
  virtual void UNSHIFT(SV **base, int items);
  virtual void SPLICE(int offset, int length, SV **top, int count);
  // index
  virtual int add(OSSVPV *);
  virtual void remove(OSSVPV *);
  virtual void configure(SV **top, int items);

  // the idea is to load in the index's configured path; why do I want this?
  // virtual void load_path(osp_pathexam *); ???
};

// simple hash slot -- use it or write your own
// a better name might have been osp_hvent2...

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

#ifdef OSPERL_PRIVATE
#define OSP_INIT(z) z
#else
#define OSP_INIT(z)
#endif

// Safe, easy, embedded, fixed maximum length strings
// Can you tell that I hate templates?
#define DECLARE_FIXEDSTRING(W)				\
struct osp_str##W {					\
  static os_typespec *get_os_typespec();		\
  static int maxlen;					\
private:						\
  os_unsigned_int8 len;					\
  char ch[ W ];						\
public:							\
  osp_str##W() { set_undef(); }				\
  void set_undef() { len=0xff; }			\
  void set(char *pv, STRLEN pvn) {			\
    len = (pvn > maxlen)? maxlen : pvn;			\
    memcpy(ch, pv, len);				\
  }							\
  void operator=(char *pv) { set(pv,strlen(pv)); }	\
  int is_undef() { return len == 0xff; }		\
  char *get(STRLEN *pvn) { *pvn=len; return ch; }	\
};							\
OSP_INIT(int osp_str##W::maxlen = W;)

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

// Safe, easy, fixed maximum length bitsets
//   Use Bit::Vector for variable length stuff
#define DECLARE_BITSET(W)					\
struct osp_bitset##W {						\
  static os_typespec *get_os_typespec();			\
private:							\
  os_unsigned_int32 bits[W];					\
public:								\
  osp_bitset##W() { clr(); }					\
  void clr() { for (int bx=0; bx < W; bx++) bits[bx]=0;	}	\
  void set() { for (int bx=0; bx < W; bx++) bits[bx]=~0; }	\
  int operator [](int bx) {					\
    assert(bx >=0 && bx < (W<<5));				\
    return bits[bx>>5] & ((os_unsigned_int32)1)<<(bx & 0x1f);	\
  }								\
  void set(int bx) {						\
    assert(bx >=0 && bx < (W<<5));				\
    bits[bx>>5] |= ((os_unsigned_int32)1)<<(bx & 0x1f);		\
  }								\
  void clr(int bx) {						\
    assert(bx >=0 && bx < (W<<5));				\
    bits[bx>>5] &= ~(((os_unsigned_int32)1)<<(bx & 0x1f));	\
  }								\
};

DECLARE_BITSET(1)
DECLARE_BITSET(2)
DECLARE_BITSET(3)
DECLARE_BITSET(4)
#undef DECLARE_BITSET

//---------------------------------------------------------------------
#if !OSSG
//---------------------------------------------------------------------

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

#define PATHEXAM_MAXKEYS 8
class osp_pathexam {
protected:
  int descending;
  int pathcnt;
  OSSVPV *pcache[PATHEXAM_MAXKEYS];
  char mode;
  int keycnt;
  char *thru;
  STRLEN thru_len;
  int tmpkey;
  // The first set of tmpkeys are used for the loaded target.
  // The seconds and third sets are used for the other records in compare.
  OSSV tmpkeys[PATHEXAM_MAXKEYS * 3]; //should never be RVs
  OSSV *keys[PATHEXAM_MAXKEYS];
  char *conflict;
  OSSVPV *target;
  
protected:
  OSSV *path_2key(int zpath, OSSVPV *obj, char mode = 'x');

public:
  osp_pathexam(int _desc = 0);
  void init(int _desc = 0);
  void load_path(OSSVPV *_paths);
  void load_args(SV **top, int items);
  int load_target(char _mode, OSSVPV *target);
  OSSV *mod_ossv(OSSV *sv);
  char *kv_string();
  void push_keys();
  void set_conflict();
  void no_conflict();
  int compare(OSSVPV *, int partial);
  // both must be valid with respect to the loaded paths
  int compare(OSSVPV *d1, OSSVPV *d2);

  char *get_thru() { return thru; }                // always null terminated
  STRLEN get_thru_len() { return thru_len - 1; }   // ignore null terminator!
  char get_mode() { return mode; }
  int get_keycnt() { return keycnt; }
  int get_pathcnt() { return pathcnt; }
  OSSV *get_key(int kx) { return keys[kx]; }
  OSSV *get_tmpkey() { return &tmpkeys[tmpkey++]; }
};

struct osp_bridge_ring {
  const void *self;
  osp_bridge_ring *next, *prev;
  osp_bridge_ring(void *_self) :self(_self) { next = prev = this; }
  ~osp_bridge_ring() { detach(); }
  int empty() { return next == this; }
  void *pop() {
    assert(!self);
    osp_bridge_ring *rg = next;
    rg->detach();
    return (void*) rg->self;
  }
  void detach() {
    if (next != this) {
      next->prev = prev;
      prev->next = next;
      next = prev = this;
    }
  }
  void attach(osp_bridge_ring *r1) {
    assert(next == this);
    next = r1->next;
    prev = r1;
    next->prev = this;
    prev->next = this;
  }
};

// ODI seemed to want to restrict tix_handlers to lexical scope.
/*No thanks:*/ struct dytix_handler { tix_handler hand; dytix_handler(); };

// per-thread globals
struct osp_thr {
  static int Version;
  static void version_check(int ver);

  osp_thr();
  ~osp_thr();

  //global globals
  static void boot();
  static HV *Schema;
  static osp_thr *fetch();
  static SV *stargate;
  static HV *CLASSLOAD;
  static SV *TXGV;
  static AV *TXStack;
  static HV *BridgeStash;

  //methods
  static void register_schema(char *cl, _Application_schema_info *sch);
  static void record_new(void *vptr, char *when, char *type, int ary=0);

  //context
  long signature;
  long debug;
  dytix_handler *hand;
  char *report;
  osp_bridge_ring ospv_freelist;
  osp_pathexam exam;

  //glue methods
  static void *default_dynacast(void *obj, HV *stash);
  static os_segment *sv_2segment(SV *);
  static ospv_bridge *sv_2bridge(SV *, int force, os_segment *near=0);
  static SV *ossv_2sv(OSSV *ossv, int hold=0);
  static SV *ospv_2sv(OSSVPV *, int hold=0);
  static SV *wrap(OSSVPV *ospv, SV *br);
  static OSSV *plant_sv(os_segment *, SV *);
  static OSSV *plant_ospv(os_segment *seg, OSSVPV *pv);
  static unsigned long sv_2aelem(SV *);

  void push_ospv(OSSVPV *pv); //depreciated?
};

struct osperl_version_check {
  osperl_version_check(int ver) { osp_thr::version_check(ver); }
};
static osperl_version_check _osperl_version_check(OSPERL_API_VERSION);

struct osp_txn {
  osp_txn(os_transaction::transaction_type_enum,
	  os_transaction::transaction_scope_enum);
  int is_aborted();
  void abort();
  void commit();
  void pop();
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
  osp_bridge_ring link;
};

#define dOSP osp_thr *osp = osp_thr::fetch()
#define dTXN							\
mysv_lock(osp_thr::TXGV);					\
osp_txn *txn = 0;						\
if (av_len(osp_thr::TXStack) >= 0) {				\
  SV *_txsv = SvRV(*av_fetch(osp_thr::TXStack,			\
			    av_len(osp_thr::TXStack), 0));	\
  txn = (osp_txn*) SvIV(_txsv);					\
}

/*
  Safety, then Speed;  There are lots of interlocking refcnts:

  - Each bridge has a refcnt to the SV that holds it's transaction.

  - Each transaction has a linked ring of bridges.

  - Each bridge has a refcnt to the persistent object, but only
    during updates (and in writable databases).

  There is a split between osp_bridge & ospv_bridge not because
  of necessity but mainly to try to form the clearest idea of
  what is happening.
 */

struct osp_bridge {
  dynacast_fn dynacast;
  osp_bridge_ring link;
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

  osp_bridge();
  void init(dynacast_fn dcfn);
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

struct osp_smart_object {
  virtual void freelist();
  virtual ~osp_smart_object();
};

// do not use as a super-class!!
struct ospv_bridge : osp_bridge {
  OSSVPV *pv;
  osp_smart_object *info;  // for cursors & such

  virtual void init(OSSVPV *_pv);
  virtual void unref();
  virtual void hold();
  virtual int is_weak();
  virtual void freelist();
  OSSVPV *ospv();
};

#endif /*OSSG*/

// These are temporary and might disappear!
extern "C" void mysv_lock(SV *sv);

#endif
