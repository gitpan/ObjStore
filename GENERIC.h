//------------------------------------------------------------OLD

// Splash collections
#include "splash.h"

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
  hent *operator=(int);
  hent *operator=(const hent &);
  void FORCEUNDEF();
};

struct OSPV_hvarray : OSPV_Generic {
  static os_typespec *get_os_typespec();
  SPList < hent > hv;
  OSPV_hvarray(int);
  virtual ~OSPV_hvarray();
  static void _boot(HV *);
  virtual OSSVPV *new_cursor(os_segment *seg);
  virtual ossv_bridge *new_bridge();
  virtual char *os_class(STRLEN *);
  virtual int get_perl_type();
  int index_of(char *key);
  int first(int start);
  virtual OSSV *FETCHp(char *key);
  virtual OSSV *STOREp(char *key, SV *value);
  virtual void DELETE(char *key);
  virtual void CLEAR();
  virtual int EXISTS(char *key);
  virtual SV *FIRST(ossv_bridge*);
  virtual SV *NEXT(ossv_bridge*);
  virtual double _percent_filled();
  virtual int _count();
  virtual OSSV *traverse(char *keyish);
  virtual void XSHARE(int on);
};

struct OSPV_hvarray_cs : OSPV_Cursor {
  static os_typespec *get_os_typespec();
  int cs;
  OSPV_hvarray_cs(OSPV_hvarray *_at);
  virtual void seek_pole(int end);
  virtual void at();
  virtual void next();
};

struct OSPV_setarray : OSPV_Generic {
  static os_typespec *get_os_typespec();
  SPList < OSSV > cv;
  OSPV_setarray(int size);
  virtual ~OSPV_setarray();
  static void _boot(HV *);
  virtual OSSVPV *new_cursor(os_segment *seg);
  virtual ossv_bridge *new_bridge();
  virtual char *os_class(STRLEN *);
  int first(int start);
  virtual void set_add(SV *);
  virtual int set_contains(SV *);
  virtual void set_rm(SV *);
  virtual SV *FIRST(ossv_bridge*);
  virtual SV *NEXT(ossv_bridge*);
  virtual void CLEAR();
  virtual double _percent_filled();
  virtual int _count();
};

struct OSPV_setarray_cs : OSPV_Cursor {
  static os_typespec *get_os_typespec();
  int cs;
  OSPV_setarray_cs(OSPV_setarray *_at);
  virtual void seek_pole(int end);
  virtual void at();
  virtual void next();
};

// ObjectStore collections
#include <ostore/coll.hh>
#include <ostore/coll/cursor.hh>
#include <ostore/coll/dict_pt.hh>

struct OSPV_hvdict : OSPV_Generic {
  static os_typespec *get_os_typespec();
  os_Dictionary < hkey, OSSV* > hv;
  OSPV_hvdict(os_unsigned_int32);
  virtual ~OSPV_hvdict();
  static void _boot(HV *);
  virtual ossv_bridge *new_bridge();
  virtual OSSVPV *new_cursor(os_segment *seg);
  virtual char *os_class(STRLEN *);
  virtual int get_perl_type();
  virtual OSSV *FETCHp(char *key);
  virtual OSSV *STOREp(char *key, SV *value);
  virtual void DELETE(char *key);
  virtual void CLEAR();
  virtual int EXISTS(char *key);
  virtual SV *FIRST(ossv_bridge*);
  virtual SV *NEXT(ossv_bridge*);
  virtual int _count();
  virtual OSSV *traverse(char *keyish);
  virtual void XSHARE(int on);
};

struct OSPV_hvdict_cs : OSPV_Cursor {
  static os_typespec *get_os_typespec();
  os_cursor cs;
  int reset_2pole;
  OSPV_hvdict_cs(OSPV_hvdict *_at);
  virtual void seek_pole(int end);
  virtual void at();
  virtual void next();
};

struct OSPV_sethash : OSPV_Generic {
  static os_typespec *get_os_typespec();
  os_set set;
  OSPV_sethash(os_unsigned_int32 size);
  virtual ~OSPV_sethash();
  static void _boot(HV *);
  virtual ossv_bridge *new_bridge();
  virtual OSSVPV *new_cursor(os_segment *seg);
  virtual char *os_class(STRLEN *);
  virtual void set_add(SV *);
  virtual int set_contains(SV *);
  virtual void set_rm(SV *);
  virtual SV *FIRST(ossv_bridge*);
  virtual SV *NEXT(ossv_bridge*);
  virtual void CLEAR();
  virtual int _count();
};

struct OSPV_sethash_cs : OSPV_Cursor {
  static os_typespec *get_os_typespec();
  os_cursor cs;
  int reset_2pole;
  OSPV_sethash_cs(OSPV_sethash *_at);
  virtual void seek_pole(int end);
  virtual void at();
  virtual void next();
};

//------------------------------------------------------------NEW

struct hvent2 {
  static os_typespec *get_os_typespec();
  char *hk;
  OSSV hv;
  hvent2();
  ~hvent2();
  void FORCEUNDEF();
  void set_undef();
  int valid() const;
  void set_key(char *nkey);
  hvent2 *operator=(int zero);
  hvent2 *operator=(const hvent2 &);
  int rank(const char *v2);
  SV *key_2sv();
};

//Splash REDUX

struct OSPV_avarray : OSPV_Generic {
  static os_typespec *get_os_typespec();
  SPList < OSSV > av;
  OSPV_avarray(int);
  virtual ~OSPV_avarray();
  static void _boot(HV *);
  virtual OSSVPV *new_cursor(os_segment *seg);
  virtual char *os_class(STRLEN *);
  virtual int get_perl_type();
  virtual OSSV *FETCHi(int xx);
  virtual OSSV *STOREi(int xx, SV *value);
  virtual SV *Pop();
  virtual SV *Unshift();
  virtual void Push(SV *);
  virtual void CLEAR();
  virtual double _percent_filled();
  virtual int _count();
  virtual OSSV *traverse(char *keyish);
  virtual void XSHARE(int on);
};

struct OSPV_avarray_cs : OSPV_Cursor {
  static os_typespec *get_os_typespec();
  int cs;
  OSPV_avarray_cs(OSPV_avarray *_at);
  virtual void seek_pole(int end);
  virtual void at();
  virtual void next();
};

struct OSPV_hvarray2 : OSPV_Generic {
  static os_typespec *get_os_typespec();
  SPList < hvent2 > hv;
  OSPV_hvarray2(int);
  virtual ~OSPV_hvarray2();
  static void _boot(HV *);
  virtual OSSVPV *new_cursor(os_segment *seg);
  virtual ossv_bridge *new_bridge();
  virtual char *os_class(STRLEN *);
  virtual int get_perl_type();
  int index_of(char *key);
  int first(int start);
  virtual OSSV *FETCHp(char *key);
  virtual OSSV *STOREp(char *key, SV *value);
  virtual void DELETE(char *key);
  virtual void CLEAR();
  virtual int EXISTS(char *key);
  virtual SV *FIRST(ossv_bridge*);
  virtual SV *NEXT(ossv_bridge*);
  virtual double _percent_filled();
  virtual int _count();
  virtual OSSV *traverse(char *keyish);
  virtual void XSHARE(int on);
};

struct OSPV_hvarray2_cs : OSPV_Cursor {
  static os_typespec *get_os_typespec();
  int cs;
  OSPV_hvarray2_cs(OSPV_hvarray2 *_at);
  virtual void seek_pole(int end);
  virtual void at();
  virtual void next();
};

