#ifndef __FatTree_h__
#define __FatTree_h__

#include "dex2tv.h"
#include "avtv.h"

struct OSPV_fattree_av : OSPV_Generic {
  static os_typespec *get_os_typespec();
  XPVTV ary;
  OSPV_fattree_av();
  ~OSPV_fattree_av();
  virtual char *os_class(STRLEN *);
  virtual char *rep_class(STRLEN *);
  virtual int get_perl_type();
  virtual OSSV *avx(int xx);
  virtual OSSV *FETCH(SV *xx);
  virtual OSSV *STORE(SV *xx, SV *value);
  virtual SV *POP();
  virtual SV *SHIFT();
  virtual void PUSH(SV **base, int items);
  virtual void UNSHIFT(SV **base, int items);
  virtual void SPLICE(int offset, int length, SV **top, int count);
  virtual void CLEAR();
  virtual int FETCHSIZE();
  virtual OSSV *traverse(char *keyish);
  virtual void XSHARE(int on);
};


struct OSPV_fatindex2 : OSPV_Generic {
  static os_typespec *get_os_typespec();
  XPVTV tv;
  OSSVPV *conf_slot;
  OSPV_fatindex2();
  virtual ~OSPV_fatindex2();
  virtual char *os_class(STRLEN *);
  virtual char *rep_class(STRLEN *len);
  virtual int get_perl_type();
  virtual void CLEAR();
  virtual void add(OSSVPV*);
  virtual void remove(OSSVPV*);
  virtual OSSVPV *FETCHx(SV *xx);
  virtual double _percent_filled();
  virtual int FETCHSIZE();
  virtual OSSVPV *new_cursor(os_segment *seg);
  virtual OSSV *traverse(char *keyish);
  virtual OSSVPV *traverse2(char *keyish);
};

struct OSPV_fatindex2_cs : OSPV_Cursor2 {
  static os_typespec *get_os_typespec();
  OSPV_fatindex2 *myfocus;
  XPVTC tc;
  OSPV_fatindex2_cs(OSPV_fatindex2 *_at);
  virtual ~OSPV_fatindex2_cs();
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
