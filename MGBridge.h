#ifndef _MGBridge_h_
#define _MGBridge_h_

/*
  WHY?

  OODB[SCALAR1 SCALAR2]
         |        |
       BRIDGE  BRIDGE
         |        |
         +--------+
             |
           XPVMG*
             |
         +--------+
         |        |
      SCALAR1 SCALAR2
  
  A bridge has two owners: perl and the current transaction.  The
  bridge and the scalar have different lifetimes.  The scalar lives
  for MIN(perl,txn), while the bridge must live for MAX(perl,txn) (or
  at least until perl is done).

  You must have a scalar refcnt, even if you never share scalar
  representations between two scalars.  The database is one owner, any
  bridges are the other owners.  The only exception might be simple
  strings, however perl does not yet support this yet, so basically
  you need a refcnt.
  
  Persistent scalar refcnts can only be updated during update
  transactions.  Fortunately, read-only transactions pose no refcnt
  issues.

  FYI: Bridges can also store transient cursors associated with
  collections.  Fortunately, colllections are beyond the scope of this
  module.  But, for example, suppose you need to iterate over a hash
  during a read transaction.  The hash is read-only, but you must
  associate a cursor with it (for efficiency).  A sub-class of a
  bridge does the trick.

 */

typedef mgscalar_vtbl MGSCALAR_VTBL;
struct mgscalar_vtbl {
  SV	*vtbl_stash;
  void (*init)(void *scalar);
  void (*refcnt_inc)(void *scalar);
  void (*refcnt_dec)(void *scalar);
};
#define VtblSTASH(v)	(v)->vtbl_stash

typedef mgbridge MGBRIDGE;

struct mgbridge {
  MGSCALAR_VTBL	*br_svtbl;
  void		(*perl_destroy)(MGBRIDGE *br);	/*called by MGBRIDGE::DESTROY*/
  MGBRIDGE	*br_next, *br_prev;
  int		br_flags;
};
#define MGBrVTBL(br)	(br)->br_vtbl
#define MGBrNEXT(br)	(br)->br_next
#define MGBrPREV(br)	(br)->br_prev
#define MGBrFLAGS(br)	(br)->br_flags

#define MGBRf_PERL	0x00000001	/*unused by perl*/
#define MGBRf_TXN	0x00000002	/*unused by txn*/

/*
  Common limitations of persistent allocators:

  - Exact width types are preferred.  Specify number of bits per
  integer when possible.  It is still mostly unresolved as to how to
  deal with 64-bit types.

  - n-bit width types generally need n-bit alignment.  For example,
  32-bit integers must usually be stored with 32-bit alignment.  The
  idea is to be as binary compatible as possible between different
  platforms.

  - Unions are not supported.  (Don't even think about it! :-)

  - Variable length structures are probably not supported.  For example:

  struct varstr {
    int refcnt;
    char string[0];  # sized via malloc
  };

  Instead, you must allocate an array separately:

  struct varstr {
    int refcnt;
    char *string;    # string = malloc(sizeof(char) * len)
  };

  - Changing the layout of structures after they are stored in a
  database is generally a nightmare.  Instead it is recommended that a
  version number be appended to the name of the structure
  (e.g. mystruct1, mystruct2, mystruct3).

 */

/*
  TODO:

  How to fetch the type & vtbl from the database, such that (void*)
  can be associated with the right implementation?

 */

#endif
