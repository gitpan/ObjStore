#include "splash.h"
#include <ostore/coll.hh>
#include <ostore/coll/dict_pt.hh>

struct OSPV_avarray : OSSVPV {
  static os_typespec *get_os_typespec();
  SPList < OSSV > av;
  OSPV_avarray(int);
  virtual ~OSPV_avarray();
  virtual char *base_class();
  virtual int get_perl_type();
  virtual SV *FETCHi(int xx);
  virtual SV *STOREi(int xx, SV *value);
  virtual void CLEAR();
  virtual double cardinality();
  virtual double percent_unused();
};

struct OSPV_setarray : OSSVPV {
  static os_typespec *get_os_typespec();
  SPList < OSSV > cv;
  OSPV_setarray(int size);
  virtual ossv_bridge *NEW_BRIDGE(OSSV *, OSSVPV *);
  virtual char *base_class();
  int first(int start);
  virtual ~OSPV_setarray();
  virtual SV *ADD(SV *);
  virtual int CONTAINS(SV *);
  virtual void REMOVE(SV *);
  virtual SV *FIRST(ossv_bridge*);
  virtual SV *NEXT(ossv_bridge*);
  virtual void CLEAR();
  virtual double cardinality();
  virtual double percent_unused();
};

struct OSPV_sethash : OSSVPV {
  static os_typespec *get_os_typespec();
  os_set set;
  OSPV_sethash(os_unsigned_int32 size);
  virtual ossv_bridge *NEW_BRIDGE(OSSV *, OSSVPV *);
  virtual char *base_class();
  virtual ~OSPV_sethash();
  virtual SV *ADD(SV *);
  virtual int CONTAINS(SV *);
  virtual void REMOVE(SV *);
  virtual SV *FIRST(ossv_bridge*);
  virtual SV *NEXT(ossv_bridge*);
  virtual void CLEAR();
  virtual double cardinality();
  virtual double percent_unused();
};

struct OSPV_hvdict : OSSVPV {
  static os_typespec *get_os_typespec();
  os_Dictionary < hkey, OSSV* > hv;
  OSPV_hvdict(os_unsigned_int32);
  virtual ossv_bridge *NEW_BRIDGE(OSSV *, OSSVPV *);
  virtual char *base_class();
  virtual int get_perl_type();
  virtual ~OSPV_hvdict();
  virtual SV *FETCHp(char *key);
  virtual char *GETSTR(char *key);
  virtual SV *STOREp(char *key, SV *value);
  virtual void DELETE(char *key);
  virtual void CLEAR();
  virtual int EXISTS(char *key);
  virtual SV *FIRST(ossv_bridge*);
  virtual SV *NEXT(ossv_bridge*);
  virtual double cardinality();
  virtual double percent_unused();
};

struct OSPV_hvarray : OSSVPV {
  static os_typespec *get_os_typespec();
  SPList < hent > hv;
  OSPV_hvarray(int);
  virtual ossv_bridge *NEW_BRIDGE(OSSV *, OSSVPV *);
  virtual ~OSPV_hvarray();
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
  virtual double cardinality();
  virtual double percent_unused();
};

