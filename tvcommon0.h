#include "osperl.h"

#define TV_PANIC		croak

#define dTYPESPEC(t) \
	static os_typespec *get_os_typespec();

#define FREE_XPVTV(tv)
#define FREE_XPVTC(tc)

#define FREE_TN(tn)		delete tn

/* You should not call these directly */
#define NEW_TCE(near,xx) \
	new(os_segment::of(near), TCE::get_os_typespec(), xx) TCE[xx]
#define FREE_TCE(tce)		delete [] tce

