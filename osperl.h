/*Copyright © 1997-1998 Joshua Nathaniel Pritikin.  All rights reserved.*/

#ifndef __osperl_h__
#define __osperl_h__

#ifdef __cplusplus
extern "C" {
#endif

#ifndef __GNUG__

#undef __attribute__
#define __attribute__(_arg_)

/* This directive is used by gcc to do extra argument checking.  It
has no affect on correctness; it is just a debugging tool.
Re-defining it to nothing avoids warnings from the solaris sunpro
compiler.  If you see warnings on your system, figure out how to force
your compiler to shut-the-fuck-up (!), and send me a patch. :-) */

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

#undef assert
#ifdef OSP_DEBUG

#define assert(what)                                              \
        if (!(what)) {                                                  \
            croak("Assertion failed: file \"%s\", line %d",             \
                __FILE__, __LINE__);                                    \
        }

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
#define assert(what)
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

// OSSV has only 16 bits to store type information.  Yikes!

// NOTE: It probably would have been slightly more efficient to make
// 0=UNDEF instead of 1=UNDEF.  At the time I felt the extra checking
// was worth it.

#define OSVt_ERROR		0	// should never be zero
#define OSVt_UNDEF		1
#define OSVt_IV32		2
#define OSVt_NV			3
#define OSVt_PV			4	// char string
#define OSVt_RV			5
#define OSVt_IV16		6
//#define OSVt_IV64??		7

#define OSVTYPEMASK		0x07
#define OSvTYPE(sv)		((sv)->_type & OSVTYPEMASK)
#define OSvTYPE_set(sv,to) \
	(sv)->_type = (((sv)->_type & ~OSVTYPEMASK) | (to & OSVTYPEMASK))

// XSHARED is undo-able until the ROCNT reach 2^16 - 10
#define OSVf_XSHARED		0x80
#define OSvFLAG_set(sv,flag,on)			\
STMT_START {					\
	if (on) ((sv)->_type |= (flag));	\
	else ((sv)->_type &= ~(flag));		\
} STMT_END
#define OSvXSHARED_set(sv,on) OSvFLAG_set(sv,OSVf_XSHARED,on)

#define OSvTRYWRITE(sv)						\
STMT_START {							\
  if ((sv)->_type & OSVf_XSHARED)				\
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
  HV *stash(int create);
  char *blessed_to(STRLEN *len);
  void fwd2rep(char *methname, SV **top, int items);
  virtual void bless(SV *);
  virtual ospv_bridge *new_bridge();
  virtual char *os_class(STRLEN *len);  //must be NULL terminated too
  virtual char *rep_class(STRLEN *len);
  virtual int get_perl_type();
  // you must implement none or both of the following:
  virtual OSSV *traverse(char *keyish);
  virtual void XSHARE(int on);
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
struct OSPV_Cursor; //XXX

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
  virtual SV *POP();
  virtual SV *SHIFT();
  virtual void PUSH(SV **base, int items);
  virtual void UNSHIFT(SV **base, int items);
  virtual void SPLICE(int offset, int length, SV **top, int count);
  // index
  virtual void add(OSSVPV *);
  virtual void remove(OSSVPV *);
  virtual void configure(SV **top, int items);
  virtual OSSVPV *FETCHx(SV *keyish);
  static OSSV *path_2key(OSSVPV *obj, OSPV_Generic *path);
  // sets : depreciated
  virtual void set_add(SV *);
  virtual int set_contains(SV *);
  virtual void set_rm(SV *);
};

#define INDEX_MAXKEYS 8

struct osp_pathref {
  OSPV_Generic *pcache[INDEX_MAXKEYS];
  OSSV *keys[INDEX_MAXKEYS];
  int keycnt;
};

struct osp_pathexam : osp_pathref {
  OSSVPV *trail[INDEX_MAXKEYS*4]; //XXX
  int failed;
  int trailcnt;
  char mode;
  osp_pathexam(OSPV_Generic *paths, OSSVPV *target, char mode);
  void abort();
  void commit();
};

#if !OSSG
#include "txn.h"

struct ospv_bridge : osp_bridge {
  OSSVPV *pv;
  int is_transient;
  int can_delete;  //is perl done with us?

  ospv_bridge(OSSVPV *_pv);
  virtual ~ospv_bridge();
  virtual void release();
  virtual void invalidate();
  virtual int ready();
  void unref();
  OSSVPV *ospv();

  // Add transient cursors here in sub-classes
};

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
