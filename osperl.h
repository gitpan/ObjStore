/*
Copyright (c) 1997 Joshua Nathaniel Pritikin.  All rights reserved.
This package is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.
*/

#ifdef __cplusplus
extern "C" {
#endif

#ifndef __GNUG__
#define __attribute__(attr)
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
#define GIMME_V            OP_GIMME(Perl_op, block_gimme())

#include <ostore/ostore.hh>

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
#endif

typedef void (*XS_t)(CV*);

enum ossvtype {
//  ossv_unused=0,
  ossv_undef=1,
  ossv_iv=2,
  ossv_nv=3,
  ossv_pv=4,
  ossv_obj=5,	// ref counted objects (containers or complex objects)
  ossv_xiv=6	// use os_int16 in OSSV instead of allocating an ossv_iv
};

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
//  int operator==(OSSV &);
  int operator==(OSSVPV *pv);
  //what
  int morph(ossvtype nty);
  ossvtype natural() const;
  int is_set();
  char *type_2pv();
  static char *type_2pv(ossvtype);
  OSSVPV *get_ospv();
  //refcnt
  int PvREFok();
  void PvREF_inc(void *foo);
  void PvREF_dec();
  //set
  void set_undef();
  void s(os_int32);
  void s(double);
  void s(char *, os_unsigned_int32 len);
  void s(OSSV *);
  void s(OSSVPV *);
  void s(ossv_bridge *mg);
  //get
  char *pv(STRLEN *lp);
  char *stringify();
};

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

#define PvFLAGS(pv)		(pv)->pad_1

#define PvINUSE(pv)		(PvFLAGS(pv) & OSPV_INUSE)
#define PvINUSE_on(pv)		(PvFLAGS(pv) |= OSPV_INUSE)
#define PvINUSE_off(pv)		(PvFLAGS(pv) &= ~OSPV_INUSE)

#define PvBLESS2(pv)		(PvFLAGS(pv) & OSPV_BLESS2)
#define PvBLESS2_on(pv)		(PvFLAGS(pv) |= OSPV_BLESS2)
#define PvBLESS2_off(pv)	(PvFLAGS(pv) &= ~OSPV_BLESS2)

struct OSSVPV : os_virtual_behavior {
  static os_typespec *get_os_typespec();
  os_unsigned_int32 _refs;
  os_unsigned_int16 _weak_refs;
  os_int16 pad_1;		//should rename to 'flags'
  char *classname;		//should be an OSSVPV*
  OSSVPV();
  virtual ~OSSVPV();
  void REF_inc();
  void REF_dec();
//  void wREF_inc();
//  void wREF_dec();
  int _is_blessed();
  char *blessed_to(STRLEN *len);
  virtual void bless(SV *);
  virtual ossv_bridge *_new_bridge(OSSVPV *);
  virtual char *os_class(STRLEN *len);  //must be NULL terminated too
  virtual int get_perl_type();
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
  OSPV_Cursor2(OSSVPV *);
  virtual char *os_class(STRLEN *len);
  virtual void seek_pole(int);
  virtual void at();
  virtual void next();
};
struct OSPV_Cursor; //XXX

// Any OSSVPV that contains pointers to other OSSVPVs (except a cursor)
// must be a container.  Also note that the STORE method must be compatible
// with the cursor output.

struct OSPV_Container : OSSVPV {
  static os_typespec *get_os_typespec();
  static void install_rep(HV *hv, const char *file, char *name, XS_t mk);
  //  virtual void _rep();
  virtual double _percent_filled();
  virtual int _count();
  virtual OSPV_Cursor *new_cursor(os_segment *seg);
};

// Generic collections support the standard perl array & hash
// collection types.  This is 1 class (instead of 2-3) because you might
// have a single collection that can be accessed as a hash or
// an array.

// Methods should return OSSV, OSPV_*, or void.  Not all methods
// conform to this convention yet.

struct OSPV_Generic : OSPV_Container {
  static os_typespec *get_os_typespec();
  // array & hash & set
  virtual void CLEAR();
  // hash & set
  virtual SV *FIRST(ossv_bridge*);
  virtual SV *NEXT(ossv_bridge*);
  // hash
  virtual SV *FETCHp(char *key);
  virtual SV *STOREp(char *key, SV *value);
  virtual void DELETE(char *key);
  virtual int EXISTS(char *key);
  // array (preliminary)
  virtual OSSV *FETCHi(int xx);
  virtual OSSV *STOREi(int xx, SV *value);
  virtual int _LENGTH();
  virtual SV *Pop();    //these will change soon
  virtual SV *Unshift();
  virtual void Push(SV *);
  virtual void Shift(SV *);
  // set (depreciated)
  virtual void add(SV *);
  virtual int contains(SV *);
  virtual void rm(SV *);
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

