/*Copyright © 1997-1998 Joshua Nathaniel Pritikin.  All rights reserved.*/

#ifndef _preamble_H_
#define _preamble_H_

#ifdef __cplusplus
extern "C" {
#endif

#ifndef __GNUG__
/* This directive is used by gcc to do extra argument checking.  It
has no affect on correctness; it is just a debugging tool.
Re-defining it to nothing avoids warnings from the solaris sunpro
compiler.  If you see warnings on your system, figure out how to force
your compiler to shut-up, and send me a patch. :-) */
#undef __attribute__
#define __attribute__(_arg_)
#endif

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#ifdef __cplusplus
}
#endif

#if !defined(dTHR)
#define dTHR extern int errno
#endif

#undef assert
#ifdef OSP_DEBUG

#define assert(what)                                              \
        if (!(what)) {                                                  \
            croak("Assertion failed: file \"%s\", line %d",             \
                __FILE__, __LINE__);                                    \
        }

#define DEBUG_refcnt(a)   if (osp_thr::fetch()->debug & 1)  a
#define DEBUG_assign(a)   if (osp_thr::fetch()->debug & 2)  a
// 0x4: see txn.h
#define DEBUG_array(a)    if (osp_thr::fetch()->debug & 8)  a
#define DEBUG_hash(a)     if (osp_thr::fetch()->debug & 16) a
#define DEBUG_set(a)      if (osp_thr::fetch()->debug & 32) a
#define DEBUG_cursor(a)   if (osp_thr::fetch()->debug & 64) a
#define DEBUG_bless(a)    if (osp_thr::fetch()->debug & 128) a
#define DEBUG_root(a)     if (osp_thr::fetch()->debug & 256) a
#define DEBUG_splash(a)   if (osp_thr::fetch()->debug & 512) a
#define DEBUG_txn(a)      if (osp_thr::fetch()->debug & 1024) a
#define DEBUG_ref(a)	  if (osp_thr::fetch()->debug & 2048) a
#define DEBUG_wrap(a)	  if (osp_thr::fetch()->debug & 4096) {a}
#define DEBUG_thread(a)	  if (osp_thr::fetch()->debug & 8192) a
#define DEBUG_index(a)	  if (osp_thr::fetch()->debug & 16384) a
#define DEBUG_norefs(a)	  if (osp_thr::fetch()->debug & 32768) a
#define DEBUG_decode(a)	  if (osp_thr::fetch()->debug & 65536) a
#else
#define assert(what)
#define DEBUG_refcnt(a)
#define DEBUG_assign(a)
#define DEBUG_array(a) 
#define DEBUG_hash(a)
#define DEBUG_set(a)
#define DEBUG_cursor(a)
#define DEBUG_bless(a)
#define DEBUG_root(a)
#define DEBUG_splash(a)
#define DEBUG_txn(a)
#define DEBUG_ref(a)
#define DEBUG_wrap(a)
#define DEBUG_thread(a)
#define DEBUG_index(a)
#define DEBUG_norefs(a)
#define DEBUG_decode(a)
#endif

#endif
