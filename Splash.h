// Splash collections
#include "splash.h"

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
//  hvent2 *operator=(int zero);
  int rank(const char *v2);
  SV *key_2sv();
};

//Splash REDUX

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
  virtual SV *Pop();
//  virtual SV *Unshift();
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
  virtual OSSVPV *new_cursor(os_segment *seg);
  virtual ospv_bridge *new_bridge();
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
