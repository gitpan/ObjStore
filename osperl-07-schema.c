#include "osperl.h"
#include "GENERIC.h"
#include <ostore/manschem.hh>

// OSSV is painful to evolve; everything else is e-z.
OS_MARK_SCHEMA_TYPE(OSSV);
// scalars
OS_MARK_SCHEMA_TYPE(OSPV_iv);
OS_MARK_SCHEMA_TYPE(OSPV_nv);
// interfaces
OS_MARK_SCHEMA_TYPE(OSPV_Container);
OS_MARK_SCHEMA_TYPE(OSPV_Generic);
// references
OS_MARK_SCHEMA_TYPE(OSPV_Ref);
OS_MARK_SCHEMA_TYPE(OSPV_Cursor);

//-------------------------------- NEW COLLECTIONS
OS_MARK_SCHEMA_TYPE(hvent2);
// splash
OS_MARK_SCHEMA_TYPE(OSPV_avarray);
OS_MARK_SCHEMA_TYPE(OSPV_avarray_cs);
OS_MARK_SCHEMA_TYPE(OSPV_hvarray2);
OS_MARK_SCHEMA_TYPE(OSPV_hvarray2_cs);

//-------------------------------- OLD COLLECTIONS
OS_MARK_SCHEMA_TYPE(hkey);
OS_MARK_SCHEMA_TYPE(hent);
// splash
OS_MARK_SCHEMA_TYPE(OSPV_hvarray);
OS_MARK_SCHEMA_TYPE(OSPV_hvarray_cs);
OS_MARK_SCHEMA_TYPE(OSPV_setarray);
OS_MARK_SCHEMA_TYPE(OSPV_setarray_cs);
// objectstore collections
OS_MARK_DICTIONARY(hkey,OSSV*);
OS_MARK_SCHEMA_TYPE(OSPV_hvdict);
OS_MARK_SCHEMA_TYPE(OSPV_hvdict_cs);
OS_MARK_SCHEMA_TYPE(OSPV_sethash);
OS_MARK_SCHEMA_TYPE(OSPV_sethash_cs);
