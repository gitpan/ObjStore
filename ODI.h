//------------------------------------------------------------ODI

// ObjectStore collections
#include <ostore/coll.hh>
#include <ostore/coll/cursor.hh>
#include <ostore/coll/dict_pt.hh>

#include "osp_hkey.h"

struct OSPV_hvdict : OSPV_Generic {
  static os_typespec *get_os_typespec();
  os_Dictionary < hkey, OSSV* > hv;
  OSPV_hvdict(os_unsigned_int32);
  virtual ~OSPV_hvdict();
  virtual ossv_bridge *new_bridge();
  virtual OSSVPV *new_cursor(os_segment *seg);
  virtual char *os_class(STRLEN *);
  virtual char *rep_class(STRLEN *);
  virtual int get_perl_type();
  virtual OSSV *hvx(char *key);
  virtual OSSV *FETCH(SV *key);
  virtual OSSV *STORE(SV *key, SV *value);
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
