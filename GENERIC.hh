#include "splash.h"
#include <ostore/coll.hh>
#include <ostore/coll/cursor.hh>
#include <ostore/coll/dict_pt.hh>

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
  // set
  virtual SV *add(SV *);
  virtual int contains(SV *);
  virtual void rm(SV *);
  // array (preliminary)
  virtual SV *FETCHi(int xx);
  virtual SV *STOREi(int xx, SV *value);
  virtual int _LENGTH(); //very depreciate
};

// Splash collections

struct OSPV_avarray : OSSVPV {
  static os_typespec *get_os_typespec();
  SPList < OSSV > av;
  OSPV_avarray(int);
  virtual ~OSPV_avarray();
  static void _boot(HV *);
  virtual char *base_class();
  virtual int get_perl_type();
  virtual SV *FETCHi(int xx);
  virtual SV *STOREi(int xx, SV *value);
  virtual int _LENGTH();
  virtual void CLEAR();
  virtual double _percent_filled();
};

struct OSPV_setarray : OSSVPV {
  static os_typespec *get_os_typespec();
  SPList < OSSV > cv;
  OSPV_setarray(int size);
  virtual ~OSPV_setarray();
  static void _boot(HV *);
  virtual ossv_bridge *_new_bridge(OSSVPV *);
  virtual char *base_class();
  int first(int start);
  virtual SV *add(SV *);
  virtual int contains(SV *);
  virtual void rm(SV *);
  virtual SV *FIRST(ossv_bridge*);
  virtual SV *NEXT(ossv_bridge*);
  virtual void CLEAR();
  virtual double _percent_filled();
};

struct OSPV_hvarray : OSSVPV {
  static os_typespec *get_os_typespec();
  SPList < hent > hv;
  OSPV_hvarray(int);
  virtual ~OSPV_hvarray();
  static void _boot(HV *);
  virtual ossv_bridge *_new_bridge(OSSVPV *);
  virtual char *base_class();
  virtual int get_perl_type();
  int index_of(char *key);
  int first(int start);
  virtual SV *FETCHp(char *key);
  virtual SV *STOREp(char *key, SV *value);
  virtual void DELETE(char *key);
  virtual void CLEAR();
  virtual int EXISTS(char *key);
  virtual SV *FIRST(ossv_bridge*);
  virtual SV *NEXT(ossv_bridge*);
  virtual double _percent_filled();
};

// ObjectStore collections

struct OSPV_hvdict : OSSVPV {
  static os_typespec *get_os_typespec();
  os_Dictionary < hkey, OSSV* > hv;
  OSPV_hvdict(os_unsigned_int32);
  virtual ~OSPV_hvdict();
  static void _boot(HV *);
  virtual ossv_bridge *_new_bridge(OSSVPV *);
  virtual OSPV_Cursor *new_cursor(os_segment *seg);
  virtual char *base_class();
  virtual int get_perl_type();
  virtual SV *FETCHp(char *key);
  virtual SV *STOREp(char *key, SV *value);
  virtual void DELETE(char *key);
  virtual void CLEAR();
  virtual int EXISTS(char *key);
  virtual SV *FIRST(ossv_bridge*);
  virtual SV *NEXT(ossv_bridge*);
  virtual char *_get_raw_string(char *key);
};

struct OSPV_hvdict_cs : OSPV_Cursor {
  static os_typespec *get_os_typespec();
  OSPV_hvdict *at;
  os_cursor cs;
  OSPV_hvdict_cs(OSPV_hvdict *_at);
  virtual ~OSPV_hvdict_cs();
  virtual SV *focus();
  virtual int more();
  virtual void first();
  virtual void next();
};

struct OSPV_sethash : OSSVPV {
  static os_typespec *get_os_typespec();
  os_set set;
  OSPV_sethash(os_unsigned_int32 size);
  virtual ~OSPV_sethash();
  static void _boot(HV *);
  virtual ossv_bridge *_new_bridge(OSSVPV *);
  virtual OSPV_Cursor *new_cursor(os_segment *seg);
  virtual char *base_class();
  virtual SV *add(SV *);
  virtual int contains(SV *);
  virtual void rm(SV *);
  virtual SV *FIRST(ossv_bridge*);
  virtual SV *NEXT(ossv_bridge*);
  virtual void CLEAR();
};

struct OSPV_sethash_cs : OSPV_Cursor {
  static os_typespec *get_os_typespec();
  OSPV_sethash *at;
  os_cursor cs;
  OSPV_sethash_cs(OSPV_sethash *_at);
  virtual ~OSPV_sethash_cs();
  virtual SV *focus();
  virtual int more();
  virtual void first();
  virtual void next();
};

