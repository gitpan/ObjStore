//------------------------------------------------------------OLD

// Splash collections
#include "splash.h"
#include "osp_hkey.h"

struct hent {
  static os_typespec *get_os_typespec();
  hkey hk;
  OSSV hv;
  void set_undef();
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
  virtual ospv_bridge *new_bridge();
  virtual char *os_class(STRLEN *);
  virtual int get_perl_type();
  int index_of(char *key);
  int first(int start);
  virtual OSSV *hvx(char *key);
  virtual OSSV *FETCH(SV *key);
  virtual OSSV *STORE(SV *key, SV *value);
  virtual void DELETE(char *key);
  virtual void CLEAR();
  virtual int EXISTS(char *key);
  virtual SV *FIRST(ospv_bridge*);
  virtual SV *NEXT(ospv_bridge*);
  virtual double _percent_filled();
  virtual int FETCHSIZE();
  virtual OSSV *traverse(char *keyish);
  virtual void ROSHARE_set(int on);
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
  virtual ospv_bridge *new_bridge();
  virtual char *os_class(STRLEN *);
  int first(int start);
  virtual void set_add(SV *);
  virtual int set_contains(SV *);
  virtual void set_rm(SV *);
  virtual SV *FIRST(ospv_bridge*);
  virtual SV *NEXT(ospv_bridge*);
  virtual void CLEAR();
  virtual double _percent_filled();
  virtual int FETCHSIZE();
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

struct OSPV_sethash : OSPV_Generic {
  static os_typespec *get_os_typespec();
  os_set set;
  OSPV_sethash(os_unsigned_int32 size);
  virtual ~OSPV_sethash();
  static void _boot(HV *);
  virtual ospv_bridge *new_bridge();
  virtual OSSVPV *new_cursor(os_segment *seg);
  virtual char *os_class(STRLEN *);
  virtual void set_add(SV *);
  virtual int set_contains(SV *);
  virtual void set_rm(SV *);
  virtual SV *FIRST(ospv_bridge*);
  virtual SV *NEXT(ospv_bridge*);
  virtual void CLEAR();
  virtual int FETCHSIZE();
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
