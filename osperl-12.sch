#include "osp-preamble.h"
#include "osperl.h"
#include "FatTree.h"
#include "ODI.h"
#include "Splash.h"
#include <ostore/manschem.hh>

// OSSV is painful to evolve; Everything else is ez!
OS_MARK_SCHEMA_TYPE(OSSV);
OS_MARK_SCHEMA_TYPE(OSPVptr);
// scalars
OS_MARK_SCHEMA_TYPE(OSPV_iv);
OS_MARK_SCHEMA_TYPE(OSPV_nv);
// interfaces
OS_MARK_SCHEMA_TYPE(OSPV_Container);
OS_MARK_SCHEMA_TYPE(OSPV_Generic);
OS_MARK_SCHEMA_TYPE(OSPV_Ref2);
OS_MARK_SCHEMA_TYPE(OSPV_Cursor2);

//-------------------------------- REFERENCES
OS_MARK_SCHEMA_TYPE(OSPV_Ref2_protect);
OS_MARK_SCHEMA_TYPE(OSPV_Ref2_hard);
//-------------------------------- GENERIC HASHKEY
OS_MARK_SCHEMA_TYPE(hvent2);

// FatTree
OS_MARK_SCHEMA_TYPE(TCE);
OS_MARK_SCHEMA_TYPE(avtn);
OS_MARK_SCHEMA_TYPE(OSPV_fattree_av)
OS_MARK_SCHEMA_TYPE(dex2tn);
OS_MARK_SCHEMA_TYPE(OSPV_fatindex2);
OS_MARK_SCHEMA_TYPE(OSPV_fatindex2_cs);

// ODI
OS_MARK_DICTIONARY(hkey,OSSV*);
OS_MARK_SCHEMA_TYPE(hkey);
OS_MARK_SCHEMA_TYPE(OSPV_hvdict);
OS_MARK_SCHEMA_TYPE(OSPV_hvdict_cs);

// Splash
OS_MARK_SCHEMA_TYPE(hvent2);
OS_MARK_SCHEMA_TYPE(OSPV_avarray);
OS_MARK_SCHEMA_TYPE(OSPV_avarray_cs);
OS_MARK_SCHEMA_TYPE(OSPV_hvarray2);
OS_MARK_SCHEMA_TYPE(OSPV_hvarray2_cs);
OS_MARK_SCHEMA_TYPE(OSPV_splashheap);
