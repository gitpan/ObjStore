#include "osperl.hh"
/* #include "osperl-old.hh" /**/
#include <ostore/manschem.hh>

OS_MARK_SCHEMA_TYPE(osperl_ospec);	// not used persistently

OS_MARK_SCHEMA_TYPE(OSSV);
OS_MARK_SCHEMA_TYPE(hkey);
OS_MARK_SCHEMA_TYPE(hent);
OS_MARK_SCHEMA_TYPE(OSPV_iv);
OS_MARK_SCHEMA_TYPE(OSPV_nv);
OS_MARK_SCHEMA_TYPE(OSPV_avarray);
OS_MARK_SCHEMA_TYPE(OSPV_hvarray);
OS_MARK_SCHEMA_TYPE(OSPV_hvdict);
OS_MARK_SCHEMA_TYPE(OSPV_setarray);
OS_MARK_SCHEMA_TYPE(OSPV_sethash);
OS_MARK_DICTIONARY(hkey,OSSV*);
