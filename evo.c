#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ostore/ostore.hh>
#include <ostore/coll.hh>
#include <ostore/schmevol.hh>
#include <ostore/mop.hh>
#include <ostore/dbutil.hh>
#include "osperl.hh"

void usage()
{
    printf("ospevo [-t] [-n] <database>\n");
    printf("  -n   nuke the work db and start a new database\n");
    printf("  -t   just the task list\n");
    exit(0);
}

void show_members(const os_class_type &c)
{
  os_List<const os_member*> mems(c.get_members());
  os_Cursor<const os_member*> cs(mems);
  const os_member *mem;
  for (mem= cs.first(); mem; mem = cs.next()) {

    TIX_HANDLE(all_exceptions)
    if (mem->get_kind() == os_member::Variable) {
      const os_member_variable &var = *mem;
      printf("var: %s\n", var.get_name());
      const os_function_type &oty = var.get_type();
      printf(" ty: %s\n", oty.get_string());

    } else if (mem->get_kind() == os_member::Function) {
      const os_member_function &fun = *mem;
      printf("fun: %s\n", fun.get_name());
      const os_type &oty = fun.get_type();
      printf(" ty: %s\n", oty.get_string());
    }
    TIX_EXCEPTION
    TIX_END_HANDLE
  }
}

void ossv_transform(void *new_obj)
{
  os_typed_pointer_void old_typed_obj = os_schema_evolution::get_unevolved_object(new_obj);
  void *old_obj = old_typed_obj;
  const os_class_type &c = old_typed_obj.get_type();
  show_members(c);

  const os_member_variable *mvar;

  /* fix union */
  int ty;
  mvar = c.find_member_variable("_type");
  if (!mvar) { printf("_type not found\n"); exit(1); }
  os_fetch(old_obj, *mvar, ty);

  if (ty == ossv_iv) {

    mvar = c.find_member_variable("iv");
    if (!mvar) { printf("iv not found\n"); exit(1); }
    os_fetch(old_obj, *mvar, ((OSSV*)new_obj)->u.iv);
  } else if (ty == ossv_nv) {

    mvar = c.find_member_variable("nv");
    if (!mvar) { printf("nv not found\n"); exit(1); }
    os_fetch(old_obj, *mvar, ((OSSV*)new_obj)->u.nv);
  } else {

    mvar = c.find_member_variable("Perl_ref");
    if (!mvar) { printf("Perl_ref not found\n"); exit(1); }
    os_fetch(old_obj, *mvar, ((OSSV*)new_obj)->u.pv.vptr);

    mvar = c.find_member_variable("len");
    if (!mvar) { printf("len not found\n"); exit(1); }
    os_fetch(old_obj, *mvar, ((OSSV*)new_obj)->u.pv.len);
  }
}

void ossvpv_transform(void *new_obj)
{
  os_typed_pointer_void old_typed_obj = os_schema_evolution::get_unevolved_object(new_obj);
  void *old_obj = old_typed_obj;
  const os_class_type &c = old_typed_obj.get_type();

  /* copy refs */
  os_fetch(old_obj, *c.find_member("refs"), ((OSSVPV*)new_obj)->refs);
}

int main(int argc, char **argv, char **)
{
  int task_list=0;
  int nuke_work=0;
  char *target;
  char *workdb = SCHEMADIR "/ospevo-work.db";

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
  target = strdup(argv[arg]);

  printf("Not yet.\n");
  exit(1);

  printf("evolving %s...\n", target);

  objectstore::initialize();
  os_dbutil::initialize();
  os_mop::initialize();
  os_collection::initialize();
  OS_ESTABLISH_FAULT_HANDLER;

  os_schema_evolution::augment_post_evol_transformers(os_transformer_binding("OSSV", ossv_transform));
  os_schema_evolution::augment_post_evol_transformers(os_transformer_binding("OSSVPV", ossvpv_transform));

  /* initiate evolution */
  if (nuke_work) os_dbutil::remove(workdb);
  if (task_list) {
    os_schema_evolution::task_list(workdb, target);
  } else {
    os_schema_evolution::evolve(workdb, target);
  }

  OS_END_FAULT_HANDLER
  return 0;
}
