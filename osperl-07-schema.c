#include "osperl.hh"
#include "GENERIC.hh"
#include <ostore/manschem.hh>

// need real evolution
OS_MARK_SCHEMA_TYPE(OSSV);
OS_MARK_SCHEMA_TYPE(hkey);
OS_MARK_SCHEMA_TYPE(hent);
OS_MARK_SCHEMA_TYPE(OSPV_iv);
OS_MARK_SCHEMA_TYPE(OSPV_nv);

// evolve by copying
OS_MARK_SCHEMA_TYPE(OSPV_avarray);
OS_MARK_SCHEMA_TYPE(OSPV_hvarray);
OS_MARK_SCHEMA_TYPE(OSPV_hvdict);
OS_MARK_SCHEMA_TYPE(OSPV_setarray);
OS_MARK_SCHEMA_TYPE(OSPV_sethash);
OS_MARK_DICTIONARY(hkey,OSSV*);

//OS_MARK_SCHEMA_TYPE(OSPV_Cursor);
//OS_MARK_SCHEMA_TYPE(OSPV_hvdict_cs);
//OS_MARK_SCHEMA_TYPE(OSPV_sethash_cs);
