// per-thread globals
struct osp_thr {
  osp_thr();
  ~osp_thr();
  static osp_thr *fetch();
  static void boot_single();

  //context
  long debug;
  HV *CLASSLOAD;
  SV *stargate;
  int tie_objects;
  struct osp_txn *txn;
  tix_handler handler;

  //methods
  int can_update();

  //glue methods
  os_segment *sv_2segment(SV *);
  ossv_bridge *sv_2bridge(SV *, int force, os_segment *seg=0);
  SV *ossv_2sv(OSSV *);
  SV *ospv_2sv(OSSVPV *);
  OSSV *plant_sv(os_segment *, SV *);
  OSSV *plant_ospv(os_segment *seg, OSSVPV *pv);
  void push_ospv(OSSVPV *pv);
};

struct osp_txn {
  osp_txn(os_transaction::transaction_type_enum,
	  os_transaction::transaction_scope_enum);
  ~osp_txn();
  void abort();
  void commit();
  void post_transaction();
  int can_update();
  void prepare_to_commit();
  int is_prepare_to_commit_invoked();
  int is_prepare_to_commit_completed();

  os_transaction::transaction_type_enum tt;
  osp_txn *up;
  ossv_bridge *bridge_top;
  os_transaction *os;
  tix_handler handler;
  int got_os_exception;
  char *report;
  int deadlocked;  //only in top_level
};

#define dOSP osp_thr *osp = osp_thr::fetch()
#define dTXN osp_txn *txn = osp->txn
