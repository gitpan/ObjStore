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
    printf("osp_evolve <workdb> <evolvedb>+\n");
    printf("    (i.e. ossevol for perl databases)\n\n");
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

int main(int argc, char **argv, char **)
{
  char *workdb = SCHEMADIR "/osp-evolve-work.db";
  os_Collection<const char*> dbs;
  int ignore_on=0;

  int arg=1;
  while (1) {
    if (argc <= arg) usage();
    break;
  }
  if (argc <= arg) usage();
  workdb = strdup(argv[arg++]);

  if (argc <= arg) usage();
  dbs.insert(strdup(argv[arg++]));

  while (!(argc <= arg)) {
    dbs.insert(strdup(argv[arg++]));
  }

  objectstore::initialize();
  OS_ESTABLISH_FAULT_HANDLER;

  os_schema_evolution::set_illegal_pointer_handler(ossv_vptr);

  // force instantiation
  new(os_database::get_transient_database(), OSPV_hvdict::get_os_typespec()) OSPV_hvdict(10);

  os_schema_evolution::evolve(workdb, dbs);
//  os_schema_evolution::task_list(workdb, dbs);
  printf("Success!\n");

  OS_END_FAULT_HANDLER
  return 0;
}
