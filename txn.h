void osp_croak(const char* pat, ...);

struct osp_bridge {
  osp_bridge *next;
  osp_bridge();
  virtual ~osp_bridge();
  virtual void release();		// if perl REFCNT == 0
  virtual void invalidate();		// when transaction ends
  virtual int ready();			// can delete bridge now?
  virtual int invalid();		// error to dereference?

#ifdef OSP_DEBUG  
  int br_debug;
#define BrDEBUG(b) b->br_debug
#define BrDEBUG_set(b,to) BrDEBUG(b)=to
#define DEBUG_bridge(br,a)   if (BrDEBUG(br) || osp_thr::fetch()->debug & 4) a
#else
#define BrDEBUG(b) 0
#define BrDEBUG_set(b,to)
#define DEBUG_bridge(br,a)
#endif
};

struct osp_txn;

// per-thread globals
struct osp_thr {
  osp_thr();
  ~osp_thr();
  static int info_key;
  static osp_thr *fetch();

  //context
  long debug;
  SV *errsv;
  HV *CLASSLOAD;
  SV *stargate;
  struct osp_txn *txn;
  tix_handler handler;
  osp_bridge *bridge_top;   //should be invalid

  //methods
  int can_update(void *);
  void destroy_bridge();

  //glue methods
  static os_segment *sv_2segment(SV *);
  static ospv_bridge *sv_2bridge(SV *, int force, os_segment *seg=0);
  static SV *ossv_2sv(OSSV *);
  static SV *ospv_2sv(OSSVPV *);
  static SV *wrap(OSSVPV *ospv, SV *br);

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
  void checkpoint();
  void post_transaction();
  int can_update(os_database *);
  int can_update(void *);
  void prepare_to_commit();
  int is_prepare_to_commit_invoked();
  int is_prepare_to_commit_completed();

  os_transaction::transaction_type_enum tt;
  osp_txn *up;
  osp_bridge *bridge_top;
  os_transaction *os;
  tix_handler handler;
  int got_os_exception;
  char *report;
  int deadlocked;  //only in top_level
};

#define dOSP osp_thr *osp = osp_thr::fetch()
#define dTXN osp_txn *txn = osp->txn

// rename ALWAYS -> FINALLY

#define OSP_START0				\
STMT_START {					\
int odi_cxx_ok=0;				\
TIX_HANDLE(all_exceptions)

#define OSP_ALWAYS0 \
odi_cxx_ok=1;							\
TIX_EXCEPTION							\
  sv_setpv(osp->errsv, tix_local_handler.get_report());		\
TIX_END_HANDLE							\

#define OSP_END0						\
if (!odi_cxx_ok) croak("ObjectStore: %s", SvPV(osp->errsv, na));\
} STMT_END;

#define OSP_ALWAYSEND0 OSP_ALWAYS0 OSP_END0
