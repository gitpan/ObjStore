#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ostore/ostore.hh>
#include <ostore/coll.hh>
#include <ostore/compact.hh>
#include <ostore/dbutil.hh>
#include "osperl.hh"

void usage()
{
    printf("who knows?\n");
    exit(0);
}

int main(int argc, char **argv, char **)
{
  int task_list=0;
  int nuke_work=0;
  char *target[10];

  /* flags */
  int arg=1;
  while (1) {
    if (argc < arg+1) usage();
    if (strcmp(argv[arg], "-t")==0) {
      task_list=1;
      arg++;
      continue;
    }
    if (strcmp(argv[arg], "-n")==0) {
      nuke_work=1;
      arg++;
      continue;
    }
    break;
  }
  if (argc < arg+1) usage();
  target[0] = strdup(argv[arg]);
  target[1] = 0;

  objectstore::initialize();
  os_dbutil::initialize();
  os_collection::initialize();
  OS_ESTABLISH_FAULT_HANDLER;

  // force instantiation
  new(os_database::get_transient_database(), OSPV_hvdict::get_os_typespec()) OSPV_hvdict(10);

  objectstore::compact(target);

  OS_END_FAULT_HANDLER
  return 0;
}
