// Splash collections
#include "splash.h"

//Splash REDUX

struct OSPV_splashheap : OSPV_Generic {
  static os_typespec *get_os_typespec();
  SPList < OSPVptr > av;
  OSPVptr conf_slot;
  OSPV_splashheap(int);
  virtual ~OSPV_splashheap();
  virtual char *os_class(STRLEN *);
  virtual char *rep_class(STRLEN *);
  virtual int get_perl_type();
  virtual int FETCHSIZE();
  virtual void CLEAR();
  virtual int add(OSSVPV*);
  virtual void SHIFT();
  virtual OSSVPV *FETCHx(SV *xx);
  virtual OSSVPV *traverse2(char *keyish);
};

struct OSPV_avarray : OSPV_Generic {
  static os_typespec *get_os_typespec();
  SPList < OSSV > av;
  OSPV_avarray(int);
  virtual ~OSPV_avarray();
  virtual OSSVPV *new_cursor(os_segment *seg);
  virtual char *os_class(STRLEN *);
  virtual char *rep_class(STRLEN *);
  virtual int get_perl_type();
  virtual OSSV *avx(int xx);
  virtual OSSV *FETCH(SV *xx);
  virtual OSSV *STORE(SV *xx, SV *value);
  virtual void POP();
  virtual void SHIFT();
  virtual void PUSH(SV **base, int items);
  virtual void UNSHIFT(SV **base, int items);
  virtual void SPLICE(int offset, int length, SV **base, int count);
  virtual void CLEAR();
  virtual int FETCHSIZE();
  virtual OSSV *traverse(char *keyish);
  virtual void ROSHARE_set(int on);
  virtual double _percent_filled();
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
  virtual OSSVPV *new_cursor(os_segment *seg);
  virtual char *os_class(STRLEN *);
  virtual char *rep_class(STRLEN *);
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

struct OSPV_hvarray2_cs : OSPV_Cursor {
  static os_typespec *get_os_typespec();
  int cs;
  OSPV_hvarray2_cs(OSPV_hvarray2 *_at);
  virtual void seek_pole(int end);
  virtual void at();
  virtual void next();
};

