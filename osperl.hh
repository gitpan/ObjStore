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

#undef DEBUG   // where did this get defined?
//#define DEBUG

typedef void (*XS_t)(CV*);

enum ossvtype {
//  ossv_unused=0,
  ossv_undef=1,
  ossv_iv=2,
  ossv_nv=3,
  ossv_pv=4,
  ossv_obj=5	// ref counted objects (containers or complex objects)
};

struct ossv_bridge;
struct OSSVPV;

// 8 bytes
struct OSSV {
  static os_typespec *get_os_typespec();
  static char strrep[32];
  void *vptr;
  os_unsigned_int16 _refs;  //unused
  os_int16 _type;

  //init
  OSSV();
  OSSV(SV *);
  OSSV(OSSV *);
  OSSV(OSSVPV *);
  ~OSSV();
  OSSV *operator=(SV *);
  OSSV *operator=(OSSV &);
  OSSV *operator=(const OSSV &);
  int operator==(OSSV &);
  int operator==(OSSVPV *pv);
  //what
  os_int32 discriminant();
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
  //get
  os_int32 as_iv();
  double as_nv();
  char *as_pv();
};
typedef OSSV OSSV_RAW;

// 8 bytes
struct hkey {
  static os_typespec *get_os_typespec();
  char *pv;
  os_unsigned_int32 len;
  hkey();
  hkey(const hkey &);
  hkey(const char *);
  hkey(const char *, os_unsigned_int32);
  ~hkey();
  int valid();
  void set_undef();
  hkey *operator=(const hkey &);
  hkey *operator=(const char *);
  void s(const char *k1, os_unsigned_int32);
  static int rank(const void *s1, const void *s2);
  static os_unsigned_int32 hash(const void *s1);
};

struct hent {
  static os_typespec *get_os_typespec();
  hkey hk;
  OSSV hv;
  hent *operator=(const hent &);
};

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
  static const os_unsigned_int32 MAX_REFCNT;
  os_unsigned_int32 _refs;
  char *classname;
  OSSVPV();
  virtual ~OSSVPV();
  void REF_inc();
  void REF_dec();
  char *get_blessing();
  virtual char *base_class();
  virtual int get_perl_type();
  virtual ossv_bridge *_new_bridge(OSSVPV *);
  virtual void _bless(char *nval);

  // TO BE MOVED

  //  virtual void _rep();
  virtual char *_get_raw_string(char *key);
  virtual double _percent_filled();
  virtual OSPV_Cursor *new_cursor(os_segment *seg);

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
  // set
  virtual SV *add(SV *);
  virtual int contains(SV *);
  virtual void rm(SV *);
  // array (preliminary)
  virtual SV *FETCHi(int xx);
  virtual SV *STOREi(int xx, SV *value);
  virtual int _LENGTH(); //very depreciate
};

struct OSPV_Container : OSSVPV {
  static os_typespec *get_os_typespec();
  //  virtual void _rep();
  virtual char *_get_raw_string(char *key);
  virtual double _percent_filled();
  virtual OSPV_Cursor *new_cursor(os_segment *seg);
};

struct OSPV_Cursor : OSSVPV {
  static os_typespec *get_os_typespec();
  virtual char *base_class();
  virtual SV *focus();
  virtual int more();
  virtual void first();
  virtual void next();
  virtual void prev();
  virtual void last();
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

typedef char RAW_STRING;

typedef void *(*MkOSPerlObj_t)(os_segment *seg, char *name, os_unsigned_int32 card);

// private global utilities (should be per-thread?)
struct osperl {
  //private
  static void boot_thread();
  static int enable_blessings;
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
  static SV *hkey_2sv(hkey *);
  static OSSV *plant_sv(os_segment *, SV *);
  static void push_ospv(OSSVPV *pv);
  static void push_key_ossv(hkey *hk, OSSV *hv);
};
#endif

