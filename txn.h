void osp_croak(const char* pat, ...);

/*
  Safety, then Speed;  There are lots of interlocking refcnts:

  - Each bridge has a refcnt to the SV that holds it's transaction.

  - Each transaction has a linked list of bridges.

  - Each bridge has a refcnt to the persistent object, but only
    during updates (and in writable databases).
 */

struct osp_txn;
struct osp_bridge {
  osp_bridge *next;
  osp_bridge();
  virtual ~osp_bridge();
  virtual void release();		// if perl REFCNT == 0
  virtual void invalidate();		// when transaction ends
  virtual int ready();			// can delete bridge now?
  virtual int invalid();		// error to dereference?

  SV *txsv;				// my transaction scope
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

struct dytix_handler {
  tix_handler hand;
  dytix_handler();
};

// per-thread globals
struct osp_thr {
  osp_thr();
  ~osp_thr();

  //global globals
  static void boot();
  static osp_thr *fetch();
  static SV *stargate;
  static HV *CLASSLOAD;
  static SV *TXGV;
  static AV *TXStack;
  static osp_bridge *bridge_top;

  //methods
  static void burn_bridge();

  //context
  long signature;
  long debug;
  SV *errsv;
  dytix_handler *hand;
  char *report;

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
  void abort();
  void commit();
  void pop();
  void burn_bridge();
  void checkpoint();
  void post_transaction();
  int can_update(os_database *);
  int can_update(void *);
  void prepare_to_commit();
  int is_prepare_to_commit_invoked();
  int is_prepare_to_commit_completed();

  os_transaction::transaction_type_enum tt;
  os_transaction::transaction_scope_enum ts;
  U32 owner;   //for local transactions
  osp_bridge *bridge_top;
  os_transaction *os;
};

#define dOSP osp_thr *osp = osp_thr::fetch()
#define dTXN							\
mysv_lock(osp_thr::TXGV);					\
osp_txn *txn = 0;						\
if (AvFILL(osp_thr::TXStack) >= 0) {				\
  SV *_txsv = SvRV(*av_fetch(osp_thr::TXStack,			\
			    AvFILL(osp_thr::TXStack), 0));	\
  txn = (osp_txn*) SvIV(_txsv);					\
}


// THESE MACROS CAN PROBABLY BE REMOVED NOW
//
// 1. REMOVE THEM
// 2. RE-TEST
// 3. GRIN

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
