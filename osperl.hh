// aim for generic & excellent scalability

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
#include <ostore/coll.hh>
#include <ostore/coll/dict_pt.hh>

#undef DEBUG   // where did this get defined?
//#define DEBUG
#include "splash.h"

enum ossvtype {
  ossv_undef=1,
  ossv_iv=2,
  ossv_nv=3,
  ossv_pv=4,
  ossv_rv=5,	// alien data (not implemented - needs MOP support)
  ossv_av=6,    // ref counted containers
  ossv_hv=7,
  ossv_cv=8     // sequential access container (not tied)
};

// why not 12 bytes?
struct OSSV {
  static os_typespec *get_os_typespec();
  static char strrep[32];
  union ossv_value {
    double nv;
    os_int32 iv;
    struct pv {
      void *vptr;
      os_unsigned_int32 len;
    } pv;
  } u;
  os_int16 _type;
  os_int16 _refs;

  //init
  OSSV();
  OSSV(SV *);
  OSSV(OSSV *);
  ~OSSV();
  OSSV *operator=(SV *);
  OSSV *operator=(const OSSV &);
  int operator==(const OSSV &);
  //what
  os_int32 discriminant();
  int morph(ossvtype nty);
  ossvtype natural() const;
  char *Type();
  os_segment *get_segment();
  //refcnt
  void REF_inc();
  void REF_dec();
  void REF_chk();
  int PvREFok();
  void PvREF_inc(void *foo=0);
  void PvREF_dec();
  //set
  void undef();
  void s(os_int32);
  void s(double);
  void s(char *, os_unsigned_int32 len);
  void s(const OSSV *);
  void new_array(char *rep);
  void new_hash(char *rep);
  void new_sack(char *rep);
  //get
  os_int32 as_iv();
  double as_nv();
  char *as_pv();
  os_unsigned_int32 as_pvn();
  SV *as_sv();
};

#define HKEY_MAXLEN 12

// 12 bytes
struct hkey {
  static os_typespec *get_os_typespec();
  char str[HKEY_MAXLEN];
  hkey();
  hkey(const hkey &);
  hkey(const char *);
  int valid();
  void undef();
  hkey *operator=(const hkey &);
  hkey *operator=(char *k1);
  SV *as_sv();
  static int rank(const void *s1, const void *s2);
  static os_unsigned_int32 hash(const void *s1);
};

struct hent {
  static os_typespec *get_os_typespec();
  hkey hk;
  OSSV hv;
  hent *operator=(const hent &);
};

// OSSVPV design concept -
//
// For each ossv_*v enumerated type, there is a corresponding imaginary abstract
// class that inherits from OSSVPV.  Then, for each abstract class there are
// various implementations.

// What is the most efficient way to manipulate the perl stack?

struct OSSVPV {
  static os_typespec *get_os_typespec();
  int _refs;
  char *classname;
  OSSVPV();
  virtual ~OSSVPV();
  void REF_inc();
  void REF_dec();
  void set_classname(char *nval);
  // sack
  virtual void ADD(SV *);
  virtual void REMOVE(SV *);
  virtual SV *FIRST();
  virtual SV *NEXT();
  // array (preliminary)
  virtual SV *FETCHi(int xx);
  virtual SV *STOREi(int xx, SV *value);
  // hash
  virtual SV *FETCHp(char *key);
  virtual SV *STOREp(char *key, SV *value);
  virtual void DELETE(char *key);
  virtual int EXISTS(char *key);
  virtual SV *FIRSTKEY();
  virtual SV *NEXTKEY(char *lastkey);
  // all
  virtual void CLEAR();
};

struct OSPV_cvarray : OSSVPV {
  static os_typespec *get_os_typespec();
  SPList < OSSV > cv;
  int cursor;
  OSPV_cvarray();
  int first(int start);
  virtual ~OSPV_cvarray();
  virtual void ADD(SV *);
  virtual void REMOVE(SV *);
  virtual SV *FIRST();
  virtual SV *NEXT();
  virtual void CLEAR();
};

struct OSPV_hvdict : OSSVPV {
  static os_typespec *get_os_typespec();
  os_Dictionary < hkey, OSSV* > hv;
  os_cursor cs;
  OSPV_hvdict();
  virtual ~OSPV_hvdict();
  virtual SV *FETCHp(char *key);
  virtual SV *STOREp(char *key, SV *value);
  virtual void DELETE(char *key);
  virtual void CLEAR();
  virtual int EXISTS(char *key);
  virtual SV *FIRSTKEY();
  virtual SV *NEXTKEY(char *lastkey);
};

struct OSPV_hvarray : OSSVPV {
  static os_typespec *get_os_typespec();
  SPList < hent > hv;
  int cursor;
  OSPV_hvarray();
  virtual ~OSPV_hvarray();
  int index_of(char *key);
  int first(int start);
  virtual SV *FETCHp(char *key);
  virtual SV *STOREp(char *key, SV *value);
  virtual void DELETE(char *key);
  virtual void CLEAR();
  virtual int EXISTS(char *key);
  virtual SV *FIRSTKEY();
  virtual SV *NEXTKEY(char *lastkey);
};
