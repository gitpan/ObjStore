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

// per thread?
#ifdef OSP_DEBUG
#define DEBUG_refcnt(a) if (osp::debug & 1)  a
#define DEBUG_assign(a) if (osp::debug & 2)  a
#define DEBUG_bridge(a) if (osp::debug & 4)  a
#define DEBUG_array(a)  if (osp::debug & 8)  a
#define DEBUG_hash(a)   if (osp::debug & 16) a
#define DEBUG_set(a)    if (osp::debug & 32) a
#define DEBUG_cursor(a) if (osp::debug & 64) a
#define DEBUG_bless(a)  if (osp::debug & 128) a
#define DEBUG_root(a)   if (osp::debug & 256) a
#define DEBUG_splash(a) if (osp::debug & 512) a
#define DEBUG_deadlock(a) if (osp::debug & 1024) a
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
#define DEBUG_deadlock(a)
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

struct OSPV_Cursor;

struct OSSVPV : os_virtual_behavior {
  static os_typespec *get_os_typespec();
  static void install_rep(HV *hv, const char *file, char *name, XS_t mk);
  os_unsigned_int32 _refs;
  os_unsigned_int16 _weak_refs;
  os_int16 pad_1;
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
  os_database *_get_database();
  int _broken();
  int deleted();
  OSSVPV *focus();
};

// A cursor must be a single composite object.  Otherwise you would
// need cursors for cursors.
//
struct OSPV_Cursor : OSPV_Ref {
  static os_typespec *get_os_typespec();
  OSPV_Cursor(OSSVPV *);
  virtual char *base_class();
  virtual void seek_pole(int);
  virtual void at();
  virtual void next();
};

// Any OSSVPV that containers pointers to other OSSVPVs (except a cursor)
// must be a container.  The STORE method must be compatible with the
// cursor output also.

struct OSPV_Container : OSSVPV {
  static os_typespec *get_os_typespec();
  //  virtual void _rep();
  virtual RAW_STRING *_get_raw_string(char *key);
  virtual double _percent_filled();
  virtual int _count();
  virtual OSPV_Cursor *new_cursor(os_segment *seg);
};

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

typedef void *(*MkOSPerlObj_t)(os_segment *seg, char *name, os_unsigned_int32 card);

// private global utilities (should be per-thread?)
struct osp {
  //private
  static const char *private_root;
  static void boot_thread();
  static long debug;
  static int to_bless;
  static HV *CLASSLOAD;
  static int rethrow_exceptions;
  static int tie_objects;
  static int txn_is_ok;
  static int is_update_txn;
  static void destroy_bridge();
  static ossv_bridge *bridge_top;
  static SV *wrap_object(OSSVPV *ospv);
  //??
  static SV *stargate;
  //public
  static ossv_bridge *sv_2bridge(SV *);
  static ossv_bridge *force_sv_2bridge(os_segment *seg, SV *nval);
  static os_segment *sv_2segment(SV *);
  static SV *ossv_2sv(OSSV *);
  static SV *ospv_2sv(OSSVPV *);
  static OSSV *plant_sv(os_segment *, SV *);
  static OSSV *plant_ospv(os_segment *seg, OSSVPV *pv);
  static void push_ospv(OSSVPV *pv);
};
#endif

