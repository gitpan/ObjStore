#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ostore/ostore.hh>
#include <ostore/coll.hh>
#include <ostore/schmevol.hh>
#include <ostore/mop.hh>
#include "osperl.h"
#include "GENERIC.h"

void usage()
{
    printf("osp_evolve [-i class] <workdb> <evolvedb>+\n");
    printf("    (i.e. ossevol for perl databases)\n\n");
    printf("    Errors like this:\n");
    printf("    \"<err-0022-0080>OSPV_avarray, on the list of classes with post evolution transformer functions, but are not currently part of any database schema. (err_schema_evolution)\"\n");
    printf("    are caused by a bug in incrementation schema evolution (now disabled).\n");
    printf("    You will need to add '-i avarray' to the command line for\n");
    printf("    each class listed.  If you add unnecessary '-i' options, your\n");
    printf("    database could become corrupted.\n");
    exit(0);
}

// cross database pointers? XXX
static void ossv_vptr(objectstore_exception &exc, char *msg, void *&vptr)
{
  if (&exc == &err_se_ambiguous_void_pointer) {
    os_path *path = os_schema_evolution::get_path_to_member(vptr);
    if (path) {
//      printf("path: %s\n", os_schema_evolution::path_name(*path));
    } else {
      printf("path: ?bug?\n");
    }
    vptr = (void*) os_schema_evolution::get_evolved_address(vptr);
    return;
  }
  exc.signal(msg);
//  os_typed_pointer_void old_typed_ptr = os_schema_evolution::get_unevolved_address(vptr);
//  const os_class_type &c = old_obj_typed_ptr.get_type();
}

static void ossv_xform(void *nobj)
{
  os_typed_pointer_void old_obj_typed_ptr = os_schema_evolution::get_unevolved_object(nobj);
  void *oobj = old_obj_typed_ptr;
  const os_class_type &c = old_obj_typed_ptr.get_type();
  const char *class_name = c.get_name();
//  printf("ossv_xform %s\n", class_name? class_name : "?");

  os_int16 _type;
  void *vptr;

  const os_member_variable *mv = c.find_member("_type");
  if (!mv) { printf("_type not found\n"); exit(1); }
  os_fetch(oobj, *mv, _type);

  if (_type != ossv_pv) return;

  mv = c.find_member("vptr");
  if (!mv) { printf("vptr not found\n"); exit(1); }
  os_fetch(oobj, *mv, vptr);

  if (!vptr) {
    printf("ossv %p of string type has no string; setting to undef\n", oobj);
  } else {
    OSSV *ossv = (OSSV*) nobj;
    os_int32 len = strlen((char*)vptr)+1;
    if (len > 32767) {
      printf("ossv %p string truncated to 32767 bytes\n", oobj);
      len = 32767;
    }
//    printf("ossv %p string length set to %d bytes\n", oobj, len);
    ossv->xiv = len-1;    //keep nulls hidden
  }
}

static void ossvpv_xform(void *nobj)
{
  os_typed_pointer_void old_obj_typed_ptr = os_schema_evolution::get_unevolved_object(nobj);
  void *oobj = old_obj_typed_ptr;
  const os_class_type &c = old_obj_typed_ptr.get_type();
  const char *class_name = c.get_name();
//  printf("ossvpv_xform %s\n", class_name? class_name : "?");
  const os_base_class *pv_base = c.find_base_class("OSSVPV");
  if (!pv_base) {
    printf("OSSVPV not found\n");
    exit(1);
  }
  const os_class_type &bc = pv_base->get_class();
  const char *base_name = bc.get_name();
//  printf(" - %s\n", base_name? base_name : "?");
  
  os_unsigned_int32 _refs;
  void *classname;

  const os_member_variable *mv = bc.find_member("_refs");
  if (!mv) { printf("_refs not found\n"); exit(1); }
  os_fetch(oobj, *mv, _refs);

  mv = bc.find_member("classname");
  if (!mv) { printf("classname not found\n"); exit(1); }
  os_fetch(oobj, *mv, classname);

  OSSVPV *pv = (OSSVPV*) nobj;
  pv->_refs = _refs;
  pv->_weak_refs = 0;
  pv->classname = (char*)classname;
}

int main(int argc, char **argv, char **)
{
  char *workdb = SCHEMADIR "/osp-evolve-work.db";
  os_Collection<const char*> dbs;
  int ignore_on=0;
  int ign_avarray=0;
  int ign_hvarray=0;
  int ign_setarray=0;
  int ign_hvdict=0;
  int ign_sethash=0;

  int arg=1;
  while (1) {
    if (argc <= arg) usage();
    if (strcmp(argv[arg], "-i")==0) {
      ignore_on=1;
      arg++;
      if (argc <= arg) usage();
      if (strcmp(argv[arg], "avarray")==0) ign_avarray=1;
      if (strcmp(argv[arg], "hvarray")==0) ign_hvarray=1;
      if (strcmp(argv[arg], "setarray")==0) ign_setarray=1;
      if (strcmp(argv[arg], "hvdict")==0) ign_hvdict=1;
      if (strcmp(argv[arg], "sethash")==0) ign_sethash=1;
      arg++;
    }
    break;
  }
  if (argc <= arg) usage();
  workdb = strdup(argv[arg++]);

  if (argc <= arg) usage();
  dbs.insert(strdup(argv[arg++]));

  while (!(argc <= arg)) {
    if (ignore_on) {
      printf("You can only evolve one database at a time when you use '-i'.\n");
      exit(0);
    }
    dbs.insert(strdup(argv[arg++]));
  }

  objectstore::initialize();
  OS_ESTABLISH_FAULT_HANDLER;

  os_schema_evolution::set_illegal_pointer_handler(ossv_vptr);

  os_schema_evolution::augment_post_evol_transformers(os_transformer_binding("OSSV", ossv_xform));
  if (!ign_avarray) os_schema_evolution::augment_post_evol_transformers(os_transformer_binding("OSPV_avarray", ossvpv_xform));
  if (!ign_hvarray) os_schema_evolution::augment_post_evol_transformers(os_transformer_binding("OSPV_hvarray", ossvpv_xform));
  if (!ign_setarray) os_schema_evolution::augment_post_evol_transformers(os_transformer_binding("OSPV_setarray", ossvpv_xform));
  if (!ign_hvdict) os_schema_evolution::augment_post_evol_transformers(os_transformer_binding("OSPV_hvdict", ossvpv_xform));
  if (!ign_sethash) os_schema_evolution::augment_post_evol_transformers(os_transformer_binding("OSPV_sethash", ossvpv_xform));

  // force instantiation
  new(os_database::get_transient_database(), OSPV_hvdict::get_os_typespec()) OSPV_hvdict(10);

  os_schema_evolution::evolve(workdb, dbs);
  printf("Success!\n");

  OS_END_FAULT_HANDLER
  return 0;
}
