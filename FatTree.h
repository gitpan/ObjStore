#ifndef __FatTree_h__
#define __FatTree_h__

#include "dextv.h"

struct OSPV_fatindex : OSPV_Generic {
  static os_typespec *get_os_typespec();
  dexXPVTV fi_tv;
  OSSVPV *conf_slot;
  OSPV_fatindex();
  virtual ~OSPV_fatindex();
  virtual char *os_class(STRLEN *);
  virtual char *rep_class(STRLEN *len);
  virtual int get_perl_type();
  virtual void CLEAR();
  virtual void add(OSSVPV*);
  virtual void remove(OSSVPV*);
  virtual OSSVPV *FETCHx(int xx);
  virtual double _percent_filled();
  virtual int _count();
  virtual OSSVPV *new_cursor(os_segment *seg);
};

struct OSPV_fatindex_cs : OSPV_Cursor2 {
  static os_typespec *get_os_typespec();
  dexXPVTC fi_tc;
  OSPV_fatindex_cs(OSPV_fatindex *_at);
  virtual ~OSPV_fatindex_cs();
  virtual OSSVPV *focus();
  virtual void moveto(I32);
  virtual void step(I32 delta);
  virtual void keys();
  virtual void at();
  virtual int seek(SV **top, int items);
  virtual I32 pos();
};

/*
ObjStore::AV [
  0,  #VERSION
  1,  #UNIQUE
  ObjStore::AV [
    ObjStore::AV [
      'name',
      'first',
    ],
    ObjStore::AV [
      'name',
      'last',
    ],
  ],
],
*/

#endif
