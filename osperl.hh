/*
Copyright (c) 1997 Joshua Nathaniel Pritikin.  All rights reserved.
This package is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.
*/

#ifdef __cplusplus
extern "C" {
#endif
#define __attribute__(attr)
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#ifdef __cplusplus
}
#endif

#include <ostore/ostore.hh>

#undef DEBUG   // where did this get defined?
//#define DEBUG

enum ossvtype {
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
  static const os_unsigned_int16 MAX_REFCNT;
  void *vptr;
  os_unsigned_int16 _refs;
  os_int16 _type;

  //init
  OSSV();		//assume refcnt=1 for arrays
  OSSV(SV *);		//refcnt=0
  OSSV(OSSV *);		//...
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
  char *type_2pv();
  static char *type_2pv(ossvtype);
  OSSVPV *get_ospv();
  //refcnt
  OSSV *REF_inc();
  void REF_dec();
  int PvREFok();
  void PvREF_inc(void *foo=0);
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

// OSSVPV design concept -
//
// For each ossv_*v enumerated type, there is a corresponding imaginary abstract
// class that inherits from OSSVPV.  Then, for each abstract class there are
// various implementations.

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
  // common to containers
  virtual char *base_class();
  virtual int get_perl_type();
  virtual double cardinality();
  virtual double percent_unused();
  virtual ossv_bridge *NEW_BRIDGE(OSSV *, OSSVPV *);
  virtual void BLESS(char *nval);
  virtual void CLEAR();
  virtual SV *FIRST(ossv_bridge*);
  virtual SV *NEXT(ossv_bridge*);
  // hash
  virtual char *GETSTR(char *key);
  virtual SV *FETCHp(char *key);
  virtual SV *STOREp(char *key, SV *value);
  virtual void DELETE(char *key);
  virtual int EXISTS(char *key);
  // set
  virtual SV *ADD(SV *);
  virtual int CONTAINS(SV *);
  virtual void REMOVE(SV *);
  // array (preliminary)
  virtual SV *FETCHi(int xx);
  virtual SV *STOREi(int xx, SV *value);
};

struct ossv_bridge {
  OSSV *sv;
  OSSVPV *pv;
  ossv_bridge(OSSV *_sv, OSSVPV *_pv);
  virtual ~ossv_bridge();
  void dump();
  void *get_location();
  OSSV *force_ossv();
  OSSVPV *ospv();
  // store transient cursors in your subclass of ossv_bridge
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
  static SV *wrap_object(OSSV *ossv, OSSVPV *ospv);
  //??
  static SV *gateway;
  //public
  static ossv_bridge *sv_2bridge(SV *);
  static ossv_bridge *force_sv_2bridge(os_segment *seg, SV *nval);
  static os_segment *sv_2segment(SV *);
  static SV *ossv_2sv(OSSV *);
  static SV *ospv_2sv(OSSV *);
  static SV *ospv_2sv(OSSVPV *);
  static SV *hkey_2sv(hkey *);
};
#endif

