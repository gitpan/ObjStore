/*Copyright © 1997-1998 Joshua Nathaniel Pritikin.  All rights reserved.*/

#ifndef __osperl_h__
#define __osperl_h__

#ifdef __cplusplus
extern "C" {
#endif

#ifndef __GNUG__

#undef __attribute__
#define __attribute__(attr)

/* This directive is used by gcc to do extra argument checking.  It
has no affect on correctness; it is just a debugging tool.
Re-defining it to nothing avoids warnings from the solaris sunpro
compiler.  If you see warnings on your system, figure out how to force
your compiler to shut-the-fuck-up, and send me a patch! */

#endif

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#ifdef __cplusplus
}
#endif

// embed.h is a little too aggressive XXX
#undef rs
#undef op
#undef GIMME_V
#define GIMME_V            OP_GIMME(Perl_op, block_gimme())  //yikes!

#if !defined(dTHR)
#define dTHR extern int errno
#endif

#undef croak
#define croak osp_croak

#include <ostore/ostore.hh>

// Merge perl and ObjectStore typedefs...
#undef I32
#define I32 os_int32
#undef U32
#define U32 os_unsigned_int32
#undef I16
#define I16 os_int16
#undef U16
#define U16 os_unsigned_int16

#ifdef OSP_DEBUG
#define DEBUG_refcnt(a)   if (osp_thr::fetch()->debug & 1)  a
#define DEBUG_assign(a)   if (osp_thr::fetch()->debug & 2)  a
#define DEBUG_bridge(a)   if (osp_thr::fetch()->debug & 4)  a
#define DEBUG_array(a)    if (osp_thr::fetch()->debug & 8)  a
#define DEBUG_hash(a)     if (osp_thr::fetch()->debug & 16) a
#define DEBUG_set(a)      if (osp_thr::fetch()->debug & 32) a
#define DEBUG_cursor(a)   if (osp_thr::fetch()->debug & 64) a
#define DEBUG_bless(a)    if (osp_thr::fetch()->debug & 128) a
#define DEBUG_root(a)     if (osp_thr::fetch()->debug & 256) a
#define DEBUG_splash(a)   if (osp_thr::fetch()->debug & 512) a
#define DEBUG_txn(a)      if (osp_thr::fetch()->debug & 1024) a
#define DEBUG_ref(a)	  if (osp_thr::fetch()->debug & 2048) a
#define DEBUG_wrap(a)	  if (osp_thr::fetch()->debug & 4096) {a}
#define DEBUG_thread(a)	  if (osp_thr::fetch()->debug & 8192) a
#define DEBUG_index(a)	  if (osp_thr::fetch()->debug & 16384) a
#else
#define DEBUG_refcnt(a)
#define DEBUG_assign(a)
#define DEBUG_bridge(a)
#define DEBUG_array(a) 
#define DEBUG_hash(a)
#define DEBUG_set(a)
#define DEBUG_cursor(a)
#define DEBUG_bless(a)
#define DEBUG_root(a)
#define DEBUG_splash(a)
#define DEBUG_txn(a)
#define DEBUG_ref(a)
#define DEBUG_wrap(a)
#define DEBUG_thread(a)
#define DEBUG_index(a)
#endif

typedef void (*XS_t)(CV*);

/* OSSV has only 16 bits to store type information. */

#define OSVt_ERROR		0	/* should never be zero */
#define OSVt_UNDEF		1
#define OSVt_IV32		2
#define OSVt_NV			3
#define OSVt_PV			4	/*char string*/
#define OSVt_RV			5
#define OSVt_IV16		6
/*#define OSVt_IV64??		7 */

#define OSVTYPEMASK		0x07
#define OSvTYPE(sv)		((sv)->_type & OSVTYPEMASK)
#define OSvTYPE_set(sv,to) \
	(sv)->_type = (((sv)->_type & ~OSVTYPEMASK) | (to & OSVTYPEMASK))

#define OSVf_XSHARED		0x80
#define OSvXSHARED(sv)		((sv)->_type & OSVf_XSHARED)
#define OSvXSHARED_on(sv)	((sv)->_type |= OSVf_XSHARED)
#define OSvXSHARED_off(sv)	((sv)->_type &= ~OSVf_XSHARED)

#define OSvTRYWRITE(sv)						\
STMT_START {							\
  if (OSvXSHARED(sv))						\
    croak("Attempt to modify READONLY %s", sv->type_2pv(), sv);	\
} STMT_END

struct ossv_bridge;
struct OSSVPV;

// 8 bytes
struct OSSV {
  static os_typespec *get_os_typespec();
  static char strrep[64];
  void *vptr;
  os_int16 xiv;
  os_int16 _type;

  //init
  OSSV();
  OSSV(SV *);
  OSSV(OSSV *);
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
  char *type_2pv();
  static char *type_2pv(int);
  OSSVPV *get_ospv();
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
  void s(ossv_bridge *mg);
  //get
  char *stringify();
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
  HV *stash();
  char *blessed_to(STRLEN *len);
  void fwd2rep(char *methname, SV **top, int items);
  virtual void bless(SV *);
  virtual ossv_bridge *new_bridge();
  virtual char *os_class(STRLEN *len);  //must be NULL terminated too
  virtual char *rep_class(STRLEN *len);
  virtual int get_perl_type();
  // you must implement none or both of the following
  virtual OSSV *traverse(char *keyish);
  virtual void XSHARE(int on);
  // methods for easy downcasting assertions
  virtual int is_array();
  virtual int is_hash();
};

struct OSPV_Ref2 : OSSVPV {
  static os_typespec *get_os_typespec();
  OSPV_Ref2();
  virtual char *os_class(STRLEN *len);
  virtual os_database *get_database();
  virtual int deleted();
  virtual OSSVPV *focus();
  virtual char *dump();
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

// A cursor must be a single composite object.  Otherwise you would
// need cursors for cursors.

struct OSPV_Cursor2 : OSSVPV {
  static os_typespec *get_os_typespec();
  virtual char *os_class(STRLEN *len);
  virtual os_database *get_database();   //might be a ref too
  virtual int deleted();
  virtual OSSVPV *focus();
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
struct OSPV_Cursor; //XXX

// Any OSSVPV that contains pointers to other OSSVPVs (except a cursor)
// must be a container.  Also note that the STORE method must be compatible
// with the cursor output (when reasonable).

struct OSPV_Container : OSSVPV {
  static os_typespec *get_os_typespec();
  static void install_rep(HV *hv, const char *file, char *name, XS_t mk);
  //  virtual void _rep();
  virtual double _percent_filled();
  virtual int _count();
  virtual void CLEAR();
  virtual OSSVPV *new_cursor(os_segment *seg);
};

// Methods should return OSSV*, OSPV_*, or void (avoid SV* !).  'void' is
// preferred and the most flexible.  Not all methods conform to this
// convention yet.

// Generic collections support the standard perl array & hash
// collection types.  This is 1 class (instead of 2-3) because you might
// have a single collection that can be accessed as a hash or
// an index or an array.  (And there is no down-side except C++ ugliness.)

struct OSPV_Generic : OSPV_Container {
  static os_typespec *get_os_typespec();
  // hash
  virtual SV *FIRST(ossv_bridge*);
  virtual SV *NEXT(ossv_bridge*);
  virtual OSSV *FETCHp(char *key);
  virtual OSSV *STOREp(char *key, SV *value);
  virtual void DELETE(char *key);
  virtual int EXISTS(char *key);
  // array (preliminary)
  virtual OSSV *FETCHi(int xx);
  virtual OSSV *STOREi(int xx, SV *value);
  virtual int _LENGTH();
  virtual SV *Pop();    //these will change
  virtual SV *Unshift();
  virtual void Push(SV *);
  virtual void Shift(SV *);
  // index
  virtual void add(OSSVPV *);
  virtual void remove(OSSVPV *);
  virtual void configure(SV **top, int items);
  virtual OSSVPV *FETCHx(int xx);
  static OSSV *path_2key(OSSVPV *obj, OSPV_Generic *path);
  // goofy
  virtual int is_array();
  virtual int is_hash();
  // sets : depreciated
  virtual void set_add(SV *);
  virtual int set_contains(SV *);
  virtual void set_rm(SV *);
};

#define INDEX_MAXKEYS 8

struct osp_pathexam {
  OSPV_Generic *pcache[INDEX_MAXKEYS];
  OSSV *keys[INDEX_MAXKEYS];
  int keycnt;
  OSSVPV *trail[INDEX_MAXKEYS];
  int trailcnt;
  char mode;
  osp_pathexam(OSPV_Generic *paths, OSSVPV *target, char mode);
  void abort();
};

struct ossv_bridge {
  ossv_bridge *next;
  OSSVPV *pv;
  int is_strong_ref;
  int is_transient;
  int can_delete;

  ossv_bridge(OSSVPV *_pv);
  virtual ~ossv_bridge();
  void dump();
  void *get_location();
  OSSVPV *ospv();
  void HOLD();
  void release();
  void unref();
  int ready();
  void invalidate(OSSVPV * = 0);

  // Add transient cursors here in sub-classes
};

#if !OSSG
#include "txn.h"
#endif

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

#endif
