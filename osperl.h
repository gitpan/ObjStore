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

typedef char RAW_STRING;

// 8 bytes
struct OSSV {
  static os_typespec *get_os_typespec();
  static char strrep[32];
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
  void bless(char *);
  //private
  RAW_STRING *get_raw_string();
  //debugging
  char *as_pv();
};
typedef OSSV OSSV_RAW;

struct OSPV_iv {
  static os_typespec *get_os_typespec();
  os_int32 iv;
};

struct OSPV_nv {
  static os_typespec *get_os_typespec();
  double nv;
};

#define OSPV_NOREFS	0x0001	/* refcnt fell to zero, running NOREFS */

#define PvFLAGS(pv)		(pv)->pad_1

#define PvNOREFS(pv)		(PvFLAGS(pv) & OSPV_NOREFS)
#define PvNOREFS_on(pv)		(PvFLAGS(pv) |= OSPV_NOREFS)
#define PvNOREFS_off(pv)	(PvFLAGS(pv) &= ~OSPV_NOREFS)

struct OSSVPV : os_virtual_behavior {
  static os_typespec *get_os_typespec();
  os_unsigned_int32 _refs;
  os_unsigned_int16 _weak_refs;
  os_int16 pad_1;		//should rename to 'flags'
  char *classname;
  OSSVPV();
  virtual ~OSSVPV();
  void REF_inc();
  void REF_dec();
  void wREF_inc();
  void wREF_dec();
  int _is_blessed();
  char *_blessed_to(int load);
  virtual void _bless(char *);
  virtual ossv_bridge *_new_bridge(OSSVPV *);
  virtual char *base_class();
  virtual int get_perl_type();
};

struct OSPV_Ref : OSSVPV {
  static os_typespec *get_os_typespec();
  OSPV_Ref(OSSVPV *);
  virtual ~OSPV_Ref();
  virtual char *base_class();
  // lock down the implementation with non-virtual methods (& for speed :-)
  os_reference_protected myfocus;
  int _broken();
  os_database *get_database();
  int deleted();
  OSSVPV *focus();
};

// A cursor must be a single composite object.  Otherwise you would
// need cursors for cursors.

struct OSPV_Cursor : OSPV_Ref {
  static os_typespec *get_os_typespec();
  OSPV_Cursor(OSSVPV *);
  virtual char *base_class();
  virtual void seek_pole(int);
  virtual void at();
  virtual void next();
};

// Any OSSVPV that contains pointers to other OSSVPVs (except a cursor)
// must be a container.  Also note that the STORE method must be compatible
// with the cursor output.

struct OSPV_Container : OSSVPV {
  static os_typespec *get_os_typespec();
  static void install_rep(HV *hv, const char *file, char *name, XS_t mk);
  //  virtual void _rep();
  virtual RAW_STRING *_get_raw_string(char *key);
  virtual double _percent_filled();
  virtual int _count();
  virtual OSPV_Cursor *new_cursor(os_segment *seg);
};

// Generic collections support the standard perl array & hash
// collection types.  This is a single class because you might
// have a single collection that can be accessed as a hash or
// an array.

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
  virtual SV *FETCHi(int xx);
  virtual SV *STOREi(int xx, SV *value);
  virtual int _LENGTH();
  virtual SV *Pop();
  virtual SV *Unshift();
  virtual void Push(SV *);
  virtual void Shift(SV *);
  // set (depreciated)
  virtual void add(SV *);
  virtual int contains(SV *);
  virtual void rm(SV *);
};

struct ossv_bridge {
  ossv_bridge *next, *prev;
  OSSVPV *pv;

  ossv_bridge(OSSVPV *_pv);
  void invalidate();
  virtual ~ossv_bridge();
  void dump();
  void *get_location();
  OSSVPV *ospv();

  // Add transient cursors here (when you sub-class)
};

#if !OSSG
#include "txn.h"
#endif
