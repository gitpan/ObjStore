# Copyright � 1997-1998 Joshua Nathaniel Pritikin.  All rights reserved.
#
# This package is free software and is provided "as is" without express
# or implied warranty.  It may be used, redistributed and/or modified
# under the terms of the Perl Artistic License (see
# http://www.perl.com/perl/misc/Artistic.html)

package ObjStore;
require 5.00404;
use strict;
use Carp;
use vars
    qw($VERSION @ISA @EXPORT @EXPORT_OK @EXPORT_FAIL %EXPORT_TAGS 
       %sizeof $INITIALIZED $RUN_TIME $OS_CACHE_DIR),
    qw($FATAL_EXCEPTIONS $SAFE_EXCEPTIONS $REGRESS),           # exceptional
    qw($SCHEMA_DB $CLIENT_NAME $CACHE_SIZE
       $TRANSACTION_PRIORITY),                                 # tied
    qw($DEFAULT_OPEN_MODE $MAX_RETRIES),                       # simulated
    qw($EXCEPTION %CLASSLOAD $CLASSLOAD $CLASS_AUTO_LOAD);     # private

$VERSION = '1.39';

$OS_CACHE_DIR = $ENV{OS_CACHE_DIR} || '/tmp/ostore';
if (!-d $OS_CACHE_DIR) {
    mkdir $OS_CACHE_DIR, 0777 
	or warn "mkdir $OS_CACHE_DIR: $!";
}

require Exporter;
require DynaLoader;
@ISA = qw(Exporter DynaLoader);
{
    my @x_adv = qw(&peek &blessed &reftype &os_version &translate 
		   &get_all_servers &set_default_open_mode &lock_timeout
		   &get_lock_status &is_lock_contention 
		  );
    my @x_tra = (qw(&fatal_exceptions &release_name
		    &network_servers_available
		    &get_max_retries &set_max_retries
		    &get_page_size &return_all_pages 
		    &abort_in_progress &get_n_databases
		    &set_stargate &DEFAULT_STARGATE
		    &PoweredByOS),
		 # depreciated
		 qw(&release_major &release_minor &release_maintenance
		    &set_transaction_priority &subscribe &unsubscribe
		   ));
    my @x_old = qw(&schema_dir);
    my @x_priv= qw($DEFAULT_OPEN_MODE %CLASSLOAD $CLASSLOAD $EXCEPTION
		   &_PRIVATE_ROOT);

    @EXPORT      = (qw(&bless &begin),
		    # depreciated
		    qw(&try_read &try_abort_only &try_update));
    @EXPORT_FAIL = ('PANIC');
    @EXPORT_OK   = (@EXPORT, @x_adv, @x_tra, @x_old, @x_priv, @EXPORT_FAIL);
    %EXPORT_TAGS = (ADV => [@EXPORT, @x_adv],
		    ALL => [@EXPORT, @x_adv, @x_tra]);
}

$EXCEPTION = sub {
    my $m = shift;
    local $Carp::CarpLevel = $Carp::CarpLevel + 1;
    if ($m eq 'SEGV') {
	$m = ObjStore::Transaction::SEGV_reason();
	$m = "ObjectStore: $m\t" if $m;
    }
    $m ||= 'SEGV';  # (probably not our fault? :-)
    warn $m if $ObjStore::REGRESS;

    # Due to bugs in perl, confess can cause a SEGV if the signal
    # happens at the wrong time.  Even a simple die doesn't always work.
    confess $m if !$ObjStore::SAFE_EXCEPTIONS;
    die $m;
};

$SIG{SEGV} = \&$EXCEPTION
    unless defined $SIG{SEGV}; # MUST NOT BE CHANGED! XXX

eval { require Thread::Specific; };
undef $@;   # only required if available
bootstrap ObjStore($VERSION);

END {
#    debug(qw(bridge txn));
    if ($INITIALIZED) {
	lock %ObjStore::Transaction::;
	my @copy = reverse @ObjStore::Transaction::Stack;
	for (@copy) { $_->abort }
	ObjStore::shutdown();
    }
}

tie $CACHE_SIZE, 'ObjStore::Config::CacheSize';
tie $CLIENT_NAME, 'ObjStore::Config::ClientName';
tie $SCHEMA_DB, 'ObjStore::Config::SchemaPath';

ObjStore::initialize() if !$ObjStore::NoInit::INIT_DELAYED;

warn "You need at least ObjectStore 4.0.1!  How were you able to compile this extension?\n" if ObjStore::os_version() < 4.0001;

require ObjStore::REP::ODI;
require ObjStore::REP::Splash;
require ObjStore::REP::FatTree;

sub export_fail {
    shift;
    if ($_[0] eq 'PANIC') { 
	require Carp;
	Carp->import('verbose');
	ObjStore::debug(shift);
    }
    @_;
}

# keywords flying coach...
sub reftype ($);
sub blessed ($);
sub bless ($;$);

tie $TRANSACTION_PRIORITY, 'ObjStore::Transaction::Priority';
sub set_transaction_priority {
    carp "just assign to \$TRANSACTION_PRIORITY directly";
    $TRANSACTION_PRIORITY = shift;
}

sub PoweredByOS {
    require Config;
    warn "PoweredByOS wont work until Makefile.PL is fixed.  Sorry.\n";
    "$Config::Config{sitelib}/ObjStore/PoweredByOS.gif"; #give it a shot... XXX
}

$FATAL_EXCEPTIONS = 1;   #happy default for newbies... (or my co-workers :-)
sub fatal_exceptions {
    my ($yes) = @_;
    if (!$FATAL_EXCEPTIONS and $yes) {
	confess "sorry, the cat's already out of the bag";
    }
    $FATAL_EXCEPTIONS = $yes;
}

$MAX_RETRIES = 10;
# goofy?
sub get_max_retries { $MAX_RETRIES; }
sub set_max_retries { $MAX_RETRIES = $_[0]; }

sub begin {
    my $code = pop @_;
    croak "last argument must be CODE" if !ref $code eq 'CODE';

    my $wantarray = wantarray;
    my @result;
    my $retries = 0;
    my $do_retry;
    do {
	@result=();
	my $txn = ObjStore::Transaction->new(@_);
	my $ok=0;
	$ok = eval {
	    if ($wantarray) {
		@result = $code->();
	    } elsif (defined $wantarray) {
		$result[0] = $code->();
	    } else {
		$code->();
	    }
	    $txn->post_transaction(); #1
	    1;
	};
	($ok and $txn->get_type !~ m'^abort') ? $txn->commit() : $txn->abort();
	$do_retry = (!$ok and $@ =~ m/Deadlock/ and $txn->top_level and
		     $retries < get_max_retries());
	++ $retries;
	die if ($@ and $FATAL_EXCEPTIONS and !$do_retry);

    } while ($do_retry);
    if (!defined wantarray) { () } else { wantarray ? @result : $result[0]; }
}

sub DEFAULT_STARGATE {
    my ($seg, $sv) = @_;
    my $type = reftype $sv;
    my $class = ref $sv;
    if ($type eq 'REF') {
	my $sv = $$sv;
	$sv->new_ref($seg, 'unsafe');  #until protected refs are fixed XXX
    } elsif ($type eq 'HASH') {
	my $pt = $class eq 'HASH' ? 'ObjStore::HV' : $class;
	$pt->new($seg, $sv);
    } elsif ($type eq 'ARRAY') {
	my $pt = $class eq 'ARRAY' ? 'ObjStore::AV' : $class;
	$pt->new($seg, $sv);
    } else {
	croak("ObjStore::DEFAULT_STARGATE: Don't know how to translate $sv");
    }
};
set_stargate(\&DEFAULT_STARGATE);

# the revised new standard bless, limited edition
sub bless ($;$) {
    my ($ref, $class) = @_;
    $class ||= scalar(caller);
    my $old = blessed $ref;
    $ref->BLESS($class) if $old;
    $class->BLESS($ref);
}
# When CORE::GLOBAL works -
#   *CORE::GLOBAL::bless = \&bless;  XXX

#sub BLESS {
#    my ($r1,$r2);
#    if (ref $r1) { warn "$r1 leaving ".ref $r1." for a new life in $r2";  }
#    else         { warn "$r2 entering $r1"; }
#    $r1->SUPER::BLESS($r2);
#}

sub require_isa_tree {
    no strict 'refs';
    my $class = shift;
    unless (@{"$class\::ISA"}) {
	my $file = $class;
	$file =~ s,::,/,g;
	eval { require "$file.pm" };
	die $@ if $@ && $@ !~ m"Can't locate .*? in \@INC";
    }
    for my $c (@{"$class\::ISA"}) { require_isa_tree($c) }
}

sub mark_unloaded {
    # Is there a hook to undo the damage if eventually loaded? XXX
    no strict;
    my $class = shift;
    warn "[marking $class as UNLOADED]\n" if $ObjStore::REGRESS;
    $ {"${class}::UNLOADED"} = 1;
    eval "package $class; ".' sub AUTOLOAD {
Carp::croak(qq[Sorry, "$AUTOLOAD" is not loaded.  You may need to adjust \@INC in order for your database code to be automatically loaded when the database is opened.\n]);
};';
    die if $@;
}

sub safe_require {
    no strict 'refs';
    my ($base, $class) = @_;
    return if $class eq 'ObjStore::Database';  #usual special case
    # We can check @ISA because all persistent classes are...
    unless (@{"$class\::ISA"}) {
	require_isa_tree($class);
	# We need to fake-up the class if it wasn't loaded.
	if (@{"${class}::ISA"} == 0) {
	    push(@{"${class}::ISA"}, $base);
	    mark_unloaded($class);
	}
    }
}

$CLASS_AUTO_LOAD = 1;

$CLASSLOAD = sub {
    my ($ignore, $base, $class) = @_;
    safe_require($base, $class) if ($base ne $class and $CLASS_AUTO_LOAD);
    $class;
};

sub disable_auto_class_loading {
    $CLASS_AUTO_LOAD = 0;
}

sub lookup {
    my ($path, $mode) = @_;
    $mode = 0 if !defined $mode;
    my $db = _lookup($path, $mode);
    if ($db && $db->is_open) {
	&ObjStore::begin(sub { $db->import_blessing(); });
	die if $@;
    }
    $db;
}

$DEFAULT_OPEN_MODE = 'update';
sub set_default_open_mode {
    my ($mode) = @_;
    croak "ObjStore::set_default_open_mode: $mode unknown"
	if $mode ne 'read' and $mode ne 'update' and $mode ne 'mvcc';
    $DEFAULT_OPEN_MODE = $mode;
}

sub open {
    my ($path, $mode, $create_mode) = @_;
    $create_mode = 0 if !defined $create_mode;
    my $db = lookup($path, $create_mode);
    if ($db) { $db->open($mode) and return $db; }
    undef;
}

sub peek {
    croak "ObjStore::peek(top)" if @_ != 1;
    require ObjStore::Peeker;
    my $pk = new ObjStore::Peeker(to => *STDERR{IO});
    $pk->Peek($_[0]);
}

sub debug {
    my $mask=0;
    for (@_) {
	/^off/    and last;
	/^refcnt/ and $mask |= 1, next;
	/^assign/ and $mask |= 2, next;
	/^bridge/ and $mask |= 4, next;
	/^array/  and $mask |= 8, next;
	/^hash/   and $mask |= 16, next;
	/^set/    and $mask |= 32, next;
	/^cursor/ and $mask |= 64, next;
	/^bless/  and $mask |= 128, next;
	/^root/   and $mask |= 0x100, next;
	/^splash/ and $mask |= 0x200, next;
	/^txn/    and $mask |= 0x400, next;
	/^ref/    and $mask |= 0x800, next;
	/^wrap/   and $mask |= 0x1000, next;
	/^thread/ and $mask |= 0x2000, next;
	/^index/  and $mask |= 0x4000, next;
	/^norefs/ and $mask |= 0x8000, next;
	/^decode/ and $mask |= 0x10000, next;
	/^PANIC/  and $mask = 0xfffff, next;
	die "Snawgrev $_ tsanik brizwah dork'ni";
    }
    if ($mask) {
	Carp->import('verbose');
    }
    $ObjStore::REGRESS = $mask != 0;
    _debug($mask);
}

#------ ------ ------ ------
sub set_cache_size {
    carp "set_cache_size() depreciated, just assign to \$CACHE_SIZE";
    $CACHE_SIZE = shift;
}
sub set_client_name {
    carp "set_client_name() depreciated, just assign to \$CLIENT_NAME";
    $CLIENT_NAME = shift;
}
sub schema_dir() {
    carp "schema_dir is depreciated.  Instead use ObjStore::Config";
    require ObjStore::Config;
    &ObjStore::Config::SCHEMA_DBDIR;
}

sub try_read(&) { 
    carp "try_read is depreciated.  Use begin('read', sub {...})";
    ObjStore::begin('read', $_[0]); ();
}
sub try_update(&) { 
    carp "try_update is depreciated.  Use begin('update', sub {...})";
    ObjStore::begin('update', $_[0]); ();
}
sub try_abort_only(&) { 
    carp "try_abort_only is depreciated.  Use begin('abort_only', sub {...})";
    ObjStore::begin('abort_only', $_[0]); ();
}
*rethrow_exceptions = \&fatal_exceptions; # depreciated
*ObjStore::disable_class_auto_loading = \&disable_auto_class_loading; #silly me

package ObjStore::Config::CacheSize;

sub TIESCALAR {
    my $p = $ENV{OS_CACHE_SIZE} || 1024 * 1024 * 8;
    bless \$p, shift;
}

sub FETCH { ${$_[0]} }
sub STORE {
    my ($o, $new) = @_;
    ObjStore::_set_cache_size($new);
    $$o = $new;
}

package ObjStore::Config::SchemaPath;

sub TIESCALAR {
    my $p;
    ObjStore::_set_application_schema_pathname($ENV{OSPERL_SCHEMA_DB})
	if $ENV{OSPERL_SCHEMA_DB};
    $p = ObjStore::_get_application_schema_pathname();
    bless \$p, shift;
}

sub FETCH { ${$_[0]} }
sub STORE {
    my ($o, $new) = @_;
    ObjStore::_set_application_schema_pathname($new);
    $$o = $new;
}

package ObjStore::Config::ClientName;

sub TIESCALAR {
    my $o = $0;
    $o =~ s,^.*/,,;
    ObjStore::_set_client_name($o);
    bless \$o, shift;
}

sub FETCH { ${$_[0]} }
sub STORE {
    my ($o, $new) = @_;
    ObjStore::_set_client_name($new);
    $$o = $new;
}

package ObjStore::Transaction::Priority;

sub TIESCALAR {
    my $p = 0x8000;
    bless \$p, shift;
}

sub FETCH { ${$_[0]} }
sub STORE {
    my ($o,$new) = @_;
    ObjStore::_set_transaction_priority($new);
    $$o = $new;
}

package ObjStore::Transaction;
use vars qw(@Stack);
#for (qw(new top_level abort commit checkpoint post_transaction
#	get_current get_type),
#     # experimental
#     qw(prepare_to_commit is_prepare_to_commit_invoked
#        is_prepare_to_commit_completed)) {
#    ObjStore::_lock_method($_)
#}

# Psuedo-class to animate persistent bless..  (Kudos to Devel::Symdump :-)
#
package ObjStore::BRAHMA;
use Carp;
use vars qw(@ISA @EXPORT %CLASS_DOGTAG);
BEGIN {
    @ISA = qw(Exporter);
    @EXPORT = (qw(&_isa &_versionof &_is_evolved &iscorrupt &stash &GLOBS
		  %CLASS_DOGTAG &_get_certified_blessing &_engineer_blessing
		  &_conjure_brahma
		 ),
	       # depreciated
	       qw(&is_corrupted));
}

'ObjStore::Database'->
    _register_private_root_key('BRAHMA', sub { 'ObjStore::HV'->new(shift, 30) });
sub _conjure_brahma { shift->_private_root_data('BRAHMA'); }

# persistent per-class globals
'ObjStore::Database'->
    _register_private_root_key('GLOBAL', sub { 'ObjStore::HV'->new(shift, 30) });
sub stash {
    my ($db, $class) = @_;
    if (!defined $class) {
	$class = ref $db;
	$db = $db->database_of;
    }
    my $G = $db->_private_root_data('GLOBAL');
    return if !$G;
    my $g = $G->{$class};
    if (!$g) {
	$g = $G->{$class} = 'ObjStore::HV'->new($G);
    }
    # can't bless what is essentially a symbol table...
    my %fake;
    tie %fake, 'ObjStore::HV', $g;
    \%fake;
}
sub GLOBS {
    carp "'GLOBS' has been renamed to 'stash'";
    stash(@_);
}

# classname => [
#   [0] = 0          (version)
#   [1] = classname  (must always be [1]; everything else can change)
#   [2] = dogtag
#   [3] = [@ISA]     (depth-first array-tree)
# ]
# classname => [
#   [0] = 1
#   [1] = classname
#   [2] = dogtag
#   [3] = [@ISA]
#   [4] = { map { $_ => $_\::VERSION } @ISA }
# ]

# We can elide the recursion check, since 
# If the persistent tree
# Has a LOOP, 
# We made a much more major mistake!
#                 -- Vogon Poetry, volume 3

sub isa_tree_matches {
    my ($class, $isa) = @_;
    no strict 'refs';
    my $x=0;
    for my $z (@{"$class\::ISA"}) {
	return 0 if (!$isa->[$x] or $isa->[$x] ne $z or
		     !isa_tree_matches($z, $isa->[$x+1]));
	$x+=2;
    }
    return if $isa->[$x+1];
    1;
}

sub _get_certified_blessing {  #XS? XXX
    my ($br, $o, $toclass) = @_;

    my $bs = $br->{$toclass};
    return if !$bs;

    return $bs if (ObjStore::blessed($o) ne $toclass and
		   ($CLASS_DOGTAG{$toclass} or 0) == $bs->[2]);

    # dogtag invalid; do a full check...

    return if ($bs->[0] != 1 ||
	       !isa_tree_matches($toclass, $bs->[3]));

    no strict 'refs';
    my $then = $bs->[4];
    for (my ($c,$v) = each %$then) {
	return if ($ {"$c\::VERSION"} || '') gt $v;
    }

    # looks good; fix dogtag so we short-cut next time
    $CLASS_DOGTAG{$toclass} = $bs->[2];
    # warn "ok $toclass ".$bs->[2];
    $bs;
}

sub isa2 { #recode in XS ? XXX
    my ($class, $isa) = @_;
    for (my $x=0; $x < $isa->FETCHSIZE; $x++) {
	my $z = $isa->[$x];
	if (ref $z) { return 1 if isa2($class, $z); }
	else { return 1 if $class eq $z; }
    }
    0;
}

sub _isa {
    my ($o, $class, $txn) = @_;
    return $o->SUPER::isa($class) if !ref $o;
    my $x = sub {
	my $bs = $o->_blessto_slot;
	return $o->SUPER::isa($class) if !$bs;
	return 1 if $class eq $bs->[1];
	isa2($class, $bs->[3]);
    };
    $txn? &ObjStore::begin($x) : &$x;
}

sub _versionof {
    my ($o, $class, $txn) = @_;
    return $o->SUPER::versionof($class) if !ref $o;
    my $x = sub {
	my $bs = $o->_blessto_slot;
	return $o->SUPER::versionof($class) if !$bs || !$bs->[4];
	$bs->[4]->{$class};
    };
    $txn? &ObjStore::begin($x) : &$x;
}

sub _is_evolved {
    my ($o, $txn) = @_;
    croak("is_evolved($o) is only meaningful on real objects") if !ref $o;
    my $x = sub {
	my $bs = $o->_blessto_slot;
	croak("is_evolved($o) only works on re-blessed objects")
	    if !$bs || !$bs->[4];
	
	no strict 'refs';
	my $then = $bs->[4];
	while (my ($c,$v) = each %$then) {
	    return if ($ {"$c\::VERSION"} || '') gt $v;
	}
	1;
    };
    $txn? &ObjStore::begin($x) : &$x;
}

# can skip the top-level class
sub isa_tree {
    my ($pkg, $depth) = @_;
    confess "ObjStore::BRAHMA::isa_tree: loop in \@$pkg\::ISA"
	if ++$depth > 100;
    my @isa;
    no strict 'refs';
    for my $z (@{"$pkg\::ISA"}) { push(@isa, $z, isa_tree($z, $depth)); }
    \@isa;
}

sub isa_versions {
    my ($pkg, $vmap, $depth) = @_;
    return $vmap if $pkg eq 'Exporter';  #apparently doesn't make sense?
    confess "ObjStore::BRAHMA::isa_versions: loop in \@$pkg\::ISA"
	if ++$depth > 100;
    no strict 'refs';
#    if (!defined $ {"$pkg\::VERSION"}) {
#	warn "\$$pkg\::VERSION must be assigned a version string!\n";
#    }
    $vmap->{$pkg} = $ {"$pkg\::VERSION"} || '0.001';
    for my $z (@{"$pkg\::ISA"}) { isa_versions($z, $vmap, $depth); }
    $vmap;
}

sub _engineer_blessing {
    my ($br, $bs, $o, $toclass) = @_;
    if (! $bs) {
	# This warning is broken since it doesn't detect the right thing
	# when there are multiple databases.  Each database needs its own copy
	# of bless-info.
#	warn "ObjStore::BRAHMA must be notified of run-time manipulation of VERSION strings by changing \$ObjStore::RUN_TIME to be != \$CLASS_DOGTAG{$toclass}" 
#	    if ($CLASS_DOGTAG{$toclass} or 0) == $ObjStore::RUN_TIME; #majify? XXX

	$bs = $br->{$toclass} =
	    [1, $toclass, $ObjStore::RUN_TIME,
	     isa_tree($toclass,0), isa_versions($toclass, {}, 0)];
	$bs->const;
	$CLASS_DOGTAG{$toclass} = $bs->[2];
#	warn "fix $toclass ".$bs->[2];
    }
    $o->_blessto_slot($bs);
}

sub iscorrupt {
    my ($o, $vlev) = @_;
    $vlev = 'all' if !defined $vlev;
    if ($vlev !~ m/^\d+$/) {
	if ($vlev eq 'quiet') { $vlev = 0; }
	elsif ($vlev eq 'err') { $vlev = 1; }
	elsif ($vlev eq 'warn') { $vlev = 2; }
	elsif ($vlev eq 'info') { $vlev = 3; }
	elsif ($vlev eq 'all') { $vlev = 4; }
	else { croak("iscorrupt($vlev): unrecognized verbosity level"); }
    }

    my $err=0;
    if ($o->can('_iscorrupt')) {
	$err += $o->_iscorrupt($vlev);
    } elsif ($o->can('_is_corrupted')) {
	warn "Please rename ".ref($o)."::_is_corrupted to _iscorrupt" if $vlev >=2;
	$err += $o->_is_corrupted($vlev);
    } else {
	warn "$o->iscorrupt: no _iscorrupt method found\n" if $vlev >= 2;
    }
    $err;
}
sub is_corrupted {
    warn "Please use iscorrupt, it's shorter too";
    iscorrupt(@_);
}

# 'bless' for databases is totally, completely, and utterly
# special-cased.  It's like stuffing a balloon inside itself.
#
package ObjStore::Database;
BEGIN { ObjStore::BRAHMA->import(); }
use Carp;
use vars qw($VERSION @OPEN0 @OPEN1 %_ROOT_KEYS);

$VERSION = '1.00';
@OPEN0=(sub { shift->sync_INC() });
@OPEN1=();

sub database_of { $_[0]; }
sub segment_of { $_[0]->get_default_segment; }

sub os_class { 'ObjStore::Database' }

sub open {
    my ($db, $mode) = @_;
    $mode = $ObjStore::DEFAULT_OPEN_MODE if !defined $mode;
    if ($mode =~ /^\d$/) {
	if ($mode == 0)    { $mode = 'update' }
	elsif ($mode == 1) { $mode = 'read' }
	else { croak "ObjStore::open($db, $mode): mode $mode??" }
    }
    my $ok=0;
    if ($mode eq 'mvcc') { $ok = $db->_open_mvcc; }
    else { $ok = $db->_open($mode eq 'read'); }
    return 0 if !$ok;

    # Acquiring a lock here messes up the deadlock regression test
    # so we check TRANSACTION_PRIORITY first.
    if ($ObjStore::TRANSACTION_PRIORITY and $ObjStore::CLASS_AUTO_LOAD) {
	&ObjStore::begin(sub {
			     for my $x (@OPEN0) { $x->($db); }
			     $db->import_blessing();
			     for my $x (@OPEN1) { $x->($db); }
			 });
	die if $@;
    }
    1;
}

'ObjStore::Database'->_register_private_root_key('INC');

sub get_INC {
    carp "EXPERIMENTAL";
    shift->_private_root_data('INC', sub { [] });
}
sub sync_INC {
    # DEPRECIATED?
    my ($db) = @_;
    my $inc = $db->_private_root_data('INC');
    return if !$inc;
    # optimize with a hash XXX
    for (my $x=0; $x < $inc->FETCHSIZE; $x++) {
	my $dir = $inc->[$x];
	my $ok=0;
	for (@INC) { $ok=1 if $_ eq $dir }
	if (!$ok) {
#	    warn "sync_INC: adding $dir";
	    unshift @INC, $dir;
	}
    }
}

sub new {
    my $class = shift;
    my $db = ObjStore::open(@_);
    ObjStore::bless($db, $class) if $db;
}

sub import_blessing {
    my ($db) = @_;
    my $bs = $db->_blessto_slot;
    if ($bs) {
	my $class = $bs->[1];
	&ObjStore::safe_require('ObjStore::Database', $class);

	# Must use CORE::bless here -- the database is _already_ blessed, yes?
	CORE::bless($db, $class);
    }
    $db;
}

'ObjStore::Database'->_register_private_root_key('database_blessed_to');
sub _blessto_slot {
    my ($db, $new) = @_;
    my $bs = $db->_private_root_data('database_blessed_to', $new);
    return if $bs && !ref $bs; #depreciated 1.19
    $bs;
}

sub isa { _isa(@_, 1); }
sub versionof { _versionof(@_, 1); }
sub is_evolved { _is_evolved(@_, 1); }

# Even though the transient blessing doesn't match, the persistent
# blessing might be correct.  We need to check before doing a super-
# slow update transaction.

# There are potentially four blessings to be aware of:
# 1. the current bless-to
# 2. the destination bless-to
# 3. the database bless-info
# 4. the per-class bless-info (in BRAHMA)

sub BLESS {
    if (ref $_[0]) {
	my ($r, $class) = @_;
	croak "Cannot bless $r into non-ObjStore::Database class '$class'"
	    if !$class->isa('ObjStore::Database');
	return $r->SUPER::BLESS($class);
    }
    my ($class, $db) = @_;
    my $need_rebless = 1;
    &ObjStore::begin(sub {
	my $br = $db->_conjure_brahma;
	return if !$br;
	my $bs = _get_certified_blessing($br, $db, $class);
	return if !$bs;
	if ($db->_blessto_slot() == $bs and $bs->[1] eq $class) {
	    # Already blessed and certified: way cool dude!
	    $need_rebless = 0;
	}
    });
    die if $@;
    no strict 'refs';
    if ($need_rebless and !$ {"$class\::UNLOADED"} and $db->is_writable) {

	&ObjStore::begin('update', sub {
		my $br = $db->_conjure_brahma;
		_engineer_blessing($br, scalar(_get_certified_blessing($br, $db, $class)), $db, $class);
	    });
	die if $@;
    }
    $class->SUPER::BLESS($db);
}

sub create_segment {
    my ($o, $name) = @_;
    carp "$o->create_segment('name')" if @_ != 2;
    my $s = $o->database_of->_create_segment;
    $s->set_comment($name) if $name;
    $s;
}

sub gc_segments {
    my ($o) = @_;
    for my $s ($o->get_all_segments()) {
	$s->destroy if $s->is_empty();
    }
}

sub destroy {
    my ($o, $step) = @_;
    $step ||= 10;
    my $more;
    do {
	&ObjStore::begin('update', sub {
	    my @r = ($o->get_all_roots, $o->_PRIVATE_ROOT);
	    for (my $x=0; $x < $step and @r; $x++) { (pop @r)->destroy }
	    $more = @r;
	});
	die if $@;
    } while ($more);

    # This doesn't work if there have been protected references!  Help!  XXX
    my $empty=1;
    &ObjStore::begin('update', sub {
	for my $s ($o->get_all_segments) {
	    next if $s->get_number == 0;   #system segment?
	    if (!$s->is_empty) {
#		warn "Segment #".$s->get_number." is not empty\n";
		$empty=0;
	    }
	}
    });
    die if $@;
    if ($empty) {
	$o->_destroy;  #secret destroy method :-)
    } else {
	croak "$o->destroy: not empty (use osrm to force the issue)";
    }
}

sub root {
    my ($o, $roottag, $nval) = @_;
    my $root = $o->find_root($roottag);
    if (defined $nval and $o->is_writable) {

	$root ||= $o->create_root($roottag);
	if (ref $nval eq 'CODE') {
	    $root->set_value(&$nval) if !defined $root->get_value();
	} else {
	    $root->set_value($nval);
	}
    }
    $root? $root->get_value() : undef;
}

sub destroy_root {
    my ($o, $tag) = @_;
    my $root = $o->find_root($tag);
    $root->destroy;
}

sub _iscorrupt {
    my ($db, $v) = @_;
    warn "$db->iscorrupt: checking...\n" if $v >= 3;
    my $err=0;
    for my $r ($db->get_all_roots()) {
	my $z = $r->get_value;
	$err += $z->iscorrupt($v);
    }
    $err;
}

sub POSH_PEEK {
    my ($val, $o, $name) = @_;
    my $path = $val->get_pathname;
    my $how = $val->is_open;
    $o->o($name."[$path, $how] {");
    $o->nl;
    $o->indent(sub {
	my @roots = sort { $a->get_name cmp $b->get_name } $val->get_all_roots;
	push(@roots, $val->_PRIVATE_ROOT) if $o->{all};
	for my $r (@roots) {
	    my $name = $o->{addr}? "$r " : '';
	    $o->o($name,$r->get_name," => ");
	    $o->peek_any($r->get_value);
	    $o->nl;
	}
	$o->{coverage} += @roots;
    });
    $o->o("},");
    $o->nl;
}

sub POSH_CD {
    my ($db, $rname) = @_;
    my $r = $db->find_root($rname);
    $r? $r->get_value : undef;
}

sub _register_private_root_key {
    my ($class, $key, $mk) = @_;
    croak "$_ROOT_KEYS{$key}->{owner} has already reserved private root key '$key'"
	if $_ROOT_KEYS{$key};
    $_ROOT_KEYS{$key} = { owner => scalar(caller), $mk? (mk => $mk):() };
}

sub _private_root_data {  #XS? XXX
    my ($db, $key, $new) = @_;
#    confess "_private_root_data(@_)" if @_ != 2 && @_ != 3;
    confess "Detected attempt to subvert security check on private root key '$key'"
	if !$_ROOT_KEYS{$key};
    my $rt = $db->_PRIVATE_ROOT();
    return if !$rt;
    my $priv = $rt->get_value;
    if (!$priv) {
	my $s = $db->create_segment("_osperl_private");
	$priv = 'ObjStore::HV'->new($s, 30);
	$rt->set_value($priv);
	$priv->{'VERSION'} = $ObjStore::VERSION; #document? XXX
    }
    if ($new) {
	if (ref $new eq 'CODE') {
	    my $d = $priv->{$key};
	    if (!$d) {
		$d = $priv->{$key} = $new->($priv);
	    }
	    $d
	} else {
	    $priv->{$key} = $new;	    
	}
    } else {
	my $d = $priv->{$key};
	if (!$d and $_ROOT_KEYS{$key}->{mk} and $db->is_writable) {
	    $d = $priv->{$key} = $_ROOT_KEYS{$key}->{mk}->($priv)
	}
	$d;
    }
}

#------- ------- ------- -------
sub is_open_read_only {
    my ($db) = @_;
    warn "$db->is_open_read_only: just use $db->is_writable or $db->is_open";
    $db->is_open eq 'read' or $db->is_open eq 'mvcc';
}

sub is_open_mvcc {
    my ($db) = @_;
    carp "$db->is_open_mvcc is unnecessary; simply use is_open";
    $db->is_open eq 'mvcc';
}

sub of {
    carp "ObjStore::Database::of() is depreciated: use the database_of method";
    $_[0]->database_of()
}
sub newHV { carp 'depreciated'; new ObjStore::HV(@_); }
sub newTiedHV { carp 'depreciated'; new ObjStore::HV(@_); }
sub newSack { carp 'depreciated'; new ObjStore::Set(@_); }

sub get_n_databases {
    carp "ObjStore::Database::get_n_databases depreciated; use ObjStore::get_n_databases";
    ObjStore::get_n_databases();
}
$_ROOT_KEYS{Brahma} = { owner => 'ObjStore::Database' }; #depreciated 1.19

package ObjStore::Segment;
use Carp;

sub segment_of { $_[0]; }
sub database_of { $_[0]->_database_of->import_blessing; }

sub destroy {
    my ($o) = @_;
    if (!$o->is_empty()) {
	croak("$o->destroy: segment not empty (you may use osp_hack if you really need to destroy it)");
    }
    $o->_destroy;
}

#------- ------- ------- ------- -------
sub of {
    carp "ObjStore::Segment::of() is depreciated: use the segment_of method";
    $_[0]->segment_of()
}
sub newHV { carp 'depreciated'; new ObjStore::HV(@_); }
sub newTiedHV { carp 'depreciated'; new ObjStore::HV(@_); }
sub newSack { carp 'depreciated'; new ObjStore::Set(@_); }

package ObjStore::Notification;
use Carp;

# Should work exactly like ObjStore::lookup
sub get_database {
    my ($n) = @_;
    my $db = $n->_get_database();
    if ($db && $db->is_open) {
	&ObjStore::begin(sub { $db->import_blessing(); });
	die if $@;
    }
    $db;
}

package ObjStore::UNIVERSAL;
BEGIN { ObjStore::BRAHMA->import(); }
use vars qw($VERSION);
$VERSION = '1.00';
use Carp;
use overload ('""' => \&_pstringify,
	      'bool' => sub {1},
	      '==' => \&_peq,
	      '!=' => \&_pneq,
#	      'nomethod' => sub { croak "overload: ".join(' ',@_); }
	     );

sub database_of { $_[0]->_database_of->import_blessing; }

*create_segment = \&ObjStore::Database::create_segment;

sub BLESS {
    return $_[0]->SUPER::BLESS($_[1])
	if ref $_[0];
    no strict 'refs';
    my ($class, $r) = @_;
    if (_is_persistent($r) and !$ {"$class\::UNLOADED"}) {
	# recode in XS ? XXX
	my $br = $r->database_of->_conjure_brahma;
	_engineer_blessing($br, scalar(_get_certified_blessing($br, $r, $class)), $r, $class);
    }
    $class->SUPER::BLESS($r);
}

sub isa { _isa(@_, 0); }
sub versionof { _versionof(@_, 0); }
sub is_evolved { _is_evolved(@_, 0); }

#shallow copy
sub clone_to { croak($_[0]."->clone_to() unimplemented") }

# Do fancy argument parsing to make creation of unsafe references a
# very intentional endevor.
sub new_ref {
    my ($o, $seg, $safe) = @_;
    $seg = $seg->segment_of if ref $seg;
    $seg = ObjStore::Segment::get_transient_segment()
	if !defined $seg;
    my $type;
    if (!defined $safe or $safe eq 'safe') { $type=0; }
    elsif ($safe eq 'unsafe' or $safe eq 'hard') { $type=1; }
    else { croak("$o->new_ref($safe,...): unknown type"); }
    $o->_new_ref($type, $seg);
}

sub help {
    '';     # reserved for posh & various
}

sub evolve {
    # Might be as simple as this:  bless $_[0], ref($_[0]);
    # but YOU have to code it!
    my ($o) = @_;
    $o->isa($o->os_class) or croak "$o must be an ".$o->os_class;
}

#-------- -------- --------
sub set_weak_refcnt_to_zero { croak "set_weak_refcnt_to_zero is unnecessary"; }
sub set_readonly { carp "set_readonly depreciated"; shift->const }

package ObjStore::Ref;
use vars qw($VERSION @ISA);
$VERSION = '1.00';
@ISA = qw(ObjStore::UNIVERSAL);

# Legal arguments:
#   dump, database
#   segment, dump, database

sub load {
    my $class = shift;
    my ($seg, $dump, $db);
    if (@_ == 2) {
	($dump, $db) = @_;
	$seg = ObjStore::Segment::get_transient_segment();
    } elsif (@_ == 3) {
	($seg, $dump, $db) = @_;
	$seg = ObjStore::Segment::get_transient_segment()
	    if !ref $seg && $seg eq 'transient';
    } else {
	croak("$class->load([segment], dump, database)");
    }
    &ObjStore::Ref::_load($class, $seg, $dump !~ m"\@", $dump, $db);
}

# Should work exactly like ObjStore::lookup
sub get_database {
    my ($r) = @_;
    my $db = $r->_get_database();
    if ($db && $db->is_open) {
	&ObjStore::begin(sub { $db->import_blessing(); });
	die if $@;
    }
    $db;
}

sub open {
    my ($r, $mode) = @_;
    my $db = $r->get_database;
    $db->open($mode) unless $db->is_open;
}

sub clone_to {
    my ($r, $seg, $cloner) = @_;
    $cloner->($r->focus)->new_ref($seg);
}

sub POSH_PEEK {
    my ($val, $o, $name) = @_;
    ++ $o->{coverage};
    $o->o("$name => ");
    $o->indent(sub {
	my $at = $val->POSH_ENTER();
	if (!ref $at) {
	    $o->o($at);
	} else {
	    $o->o(ref($at)." ...");
#	    $o->peek_any($at); XXX peek styles
	}
    });
    $o->nl;
}

sub POSH_ENTER {
    my ($val) = @_;
    my $at = '(database not found)';
    my $ok = 0;
    $ok = ObjStore::begin(sub {
	my $db = $val->get_database;
	$at = '(deleted object in '.$db->get_pathname.')';
	$db->open($val->database_of->is_open) if !$db->is_open;
	!$val->deleted;
    });
    $at = $val->focus if $ok;
    $at;
}

package ObjStore::Cursor;
use vars qw($VERSION @ISA);
$VERSION = '1.00';
@ISA = qw(ObjStore::UNIVERSAL);

sub count { $_[0]->focus->FETCHSIZE; }

sub clone_to {
    my ($r, $seg, $cloner) = @_;
    $cloner->($r->focus)->new_cursor($seg);
}

package ObjStore::Container;
use vars qw($VERSION @ISA);
$VERSION = '1.00';
@ISA = qw(ObjStore::UNIVERSAL);

sub new_cursor {
    my ($o, $seg) = @_;
    $seg = ObjStore::Segment::get_transient_segment()
	if !defined $seg || (!ref $seg and $seg eq 'transient');
    $o->_new_cursor($seg->segment_of);
}

sub clone_to {
    my ($o, $where) = @_;
    my $class = ref($o) || $o;
    $class->new($where, $o->FETCHSIZE() || 1);
}

sub count { shift->FETCHSIZE; }  #goofy XXX

package ObjStore::AV;
use Carp;
use vars qw($VERSION @ISA %REP);
$VERSION = '1.01';
@ISA=qw(ObjStore::Container);

# will build at compile time... XXX
sub new {
    my ($this, $loc, $how) = @_;
    $loc = $loc->segment_of;
    my $class = ref($this) || $this;
    my ($av, $sz, $init);
    if (ref $how) {
	$sz = @$how || 7;
	$init = $how;
    } else {
	$sz = $how || 7;
    }
    if ($sz < 45) {
	$av = ObjStore::REP::Splash::AV::new($class, $loc, $sz);
    } else {
	$av = ObjStore::REP::FatTree::AV::new($class, $loc, $sz);
    }
    if ($init) {
	for (my $x=0; $x < @$init; $x++) { $av->STORE($x, $init->[$x]); }
    }
    $av;
}

sub EXTEND {}  #todo XXX

sub _iscorrupt {
    my ($o, $vlev) = @_;
    warn "$o->iscorrupt: checking...\n" if $vlev >= 3;
    my $err=0;
    for (my $z=0; $z < $o->FETCHSIZE; $z++) {
	my $e = $o->[$z];
	$err += $e->iscorrupt($vlev) if ObjStore::blessed($e);
    }
    $err;
}

sub map {
    my ($o, $sub) = @_;
    my @r;
    for (my $x=0; $x < $o->FETCHSIZE; $x++) { push(@r, $sub->($o->[$x])); }
    @r;
}

#-------------- -------------- -------------- -------------- DEPRECIATED
sub _count { 
    carp "_count should be done directly" if $] >= 5.00457;
    $_[0]->FETCHSIZE();
}
sub _Push { 
    carp "_Push should be done directly" if $] >= 5.00457;
    shift->PUSH(@_) 
}
sub _Pop { 
    carp "_Pop should be done directly" if $] >= 5.00457;
    shift->POP(@_) 
}

package ObjStore::HV;
use Carp;
use vars qw($VERSION @ISA %REP);
$VERSION = '1.01';
@ISA=qw(ObjStore::Container);

# will build at compile time... XXX
sub new {
    my ($this, $loc, $how) = @_;
    $loc = $loc->segment_of;
    my $class = ref($this) || $this;
    my ($hv, $sz, $init);
    if (ref $how) {
	$sz = (split(m'/', scalar %$how))[0] || 7;
	$init = $how;
    } else {
	$sz = $how || 7;
    }
    if ($sz < 25) {
	$hv = ObjStore::REP::Splash::HV::new($class, $loc, $sz);
    } else {
	$hv = ObjStore::REP::ODI::HV::new($class, $loc, $sz);
    }
    if ($init) {
	while (my($hk,$v) = each %$init) { $hv->STORE($hk, $v); }
    }
    $hv;
}

sub TIEHASH {
    my ($class, $object) = @_;
    $object;
}

sub _iscorrupt {
    my ($o, $vlev) = @_;
    warn "$o->iscorrupt: checking...\n" if $vlev >= 3;
    my $err=0;
    while (my($k,$v) = each %$o) {
	$err += $v->iscorrupt($vlev) if ObjStore::blessed($v);
    }
    $err;
}

sub map {
    my ($o, $sub) = @_;
    carp "Experimental API";
    my @r;
    while (my ($k,$v) = each %$o) {
	push(@r, $sub->($v));       #pass $k too? XXX
    }
    @r;
}

#----------- ----------- ----------- ----------- ----------- -----------

sub nextKey {
    my ($o, $key) = @_;
    carp "$o->nextKey($key): depreciated";
    return $key if !exists $o->{$key};
    my $x=2;
    $x = $1 if $key =~ s/\b\s\( (\d+) \)$//x;
    while (1) {
	my $try = "$key ($x)";
	return $try if !exists $o->{$try};
	++$x;
    }
}

package ObjStore::Index;
use Carp;
use vars qw($VERSION @ISA %REP);
$VERSION = '1.00';
@ISA='ObjStore::Container';

# HashIndex will probably be a separate class? XXX
sub new {
    my ($this, $loc, @CONF) = @_;
    $loc = $loc->segment_of;
    my $class = ref($this) || $this;
    # How should this work by default?
    my $x;
    if (@CONF) {
	if (ref $CONF[0]) { #new
	    my $c = $CONF[0];
	    my $sz = $c->{size} || 100;

	    $x = ObjStore::REP::FatTree::Index::new($class, $loc);
	    $x->configure($c);
	} else {
	    # depreciated? XXX
	    $x = ObjStore::REP::FatTree::Index::new($class, $loc);
	    $x->configure(@CONF);
	}
    } else {
	$x = ObjStore::REP::FatTree::Index::new($class, $loc);
    }
    $x;
}

# optimize!! XXX
sub SHIFT {
    my ($o) = @_;
    return if !@$o;
    my $e = $o->[0];
    $o->remove($e);
    $e;
}
sub POP {
    my ($o) = @_;
    return if !@$o;
    my $e = $o->[$#$o];
    $o->remove($e);
    $e;
}

sub map {
    my ($o, $sub) = @_;
    my @r;
    for (my $x=0; $x < $o->FETCHSIZE; $x++) { push(@r, $sub->($o->[$x])); }
    @r;
}

sub POSH_PEEK {
    my ($val, $o, $name) = @_;
    $o->{coverage} += $val->FETCHSIZE;
    my $big = $val->FETCHSIZE > $o->{width};
    my $limit = $big? $o->{summary_width} : $val->FETCHSIZE;

    $o->o("$name ");
    $val->configure()->POSH_PEEK($o);
    $o->o(" [");
    $o->nl;
    $o->indent(sub {
		   my $c = $val->new_cursor;
		   $c->moveto(-1);
		   for (1..$limit) {
		       $o->peek_any($c->each(1));
		       $o->nl;
		   }
		   if ($big) { $o->o("..."); $o->nl; }
	       });
    $o->o("],");
    $o->nl;
}

sub _iscorrupt {0}  #write your own!

#----------- ----------- ----------- ----------- ----------- -----------

# only for indices keyed by a single string
sub nextKey {
    my ($o,$key) = @_;
    carp "$o->nextKey($key): depreciated";
    my $c = $o->new_cursor();
    return $key if !$c->seek($key);
    my $x=2;
    $x = $1 if $key =~ s/\b\s\( (\d+) \)$//x;
    while (1) {
	my $try = "$key ($x)";
	return $try if !$c->seek($try);
	++$x;
    }
}

sub _count { 
    carp "_count can be done directly" if $] >= 5.00457;
    $_[0]->FETCHSIZE();
}

package ObjStore::Database::HV;
sub new { die "ObjStore::Database::HV has been renamed to ObjStore::HV::Database" }
sub BLESS {
    return $_[0]->SUPER::BLESS($_[1]) if ref $_[0];
    my ($class, $db) = @_;
    $class = 'ObjStore::HV::Database';
    $class->SUPER::BLESS($db);
}

package ObjStore::DEPRECIATED::Cursor;
use Carp;
use vars qw($VERSION);
$VERSION = '0.00';

sub seek_pole {
    my $o = shift;
    carp "$o->seek_pole: used moveto instead (renamed)";
    $o->moveto(@_);
}

sub step {
    my ($o, $delta) = @_;
    $delta == 1 or carp "$o doesn't really support step";
    $o->next;
}

package ObjStore::Set;
use Carp;
use base 'ObjStore::HV';
use vars qw($VERSION);
$VERSION = '0.00';

sub new {
    carp "ObjStore::Set is depreciated";
    require ObjStore::SetEmulation;
    my $class = shift;
    bless('ObjStore::SetEmulation'->new(@_), $class);
}

sub POSH_PEEK {
    my ($val, $o, $name) = @_;
    my @S;
    my $x=0;
    for (my $v=$val->first; $v; $v=$val->next) {
	++ $o->{coverage};
	last if $x++ > $o->{width}+1;
	push(@S, $v);
    }
    my $big = @S > $o->{width};
    my $limit = $big ? $o->{summary_width}-1 : @S;
    
    $o->o($name . " [");
    $o->nl;
    ++$o->{level};
    for (my $v=$val->first; $v; $v=$val->next) {
	last if $limit-- <= 0;
	$o->peek_any($v);
	$o->nl;
    }
    if ($big) {
	$o->o("...");
	$o->nl;
    }
    --$o->{level};
    $o->o("],");
    $o->nl;
}

sub a { add(@_) }
sub r { rm($_[0], $_[1]) }
sub STORE { add(@_) }

#----------- ----------- ----------- ----------- ----------- -----------
package ObjStore;
$RUN_TIME = time;
die "RUN_TIME must be positive" if $RUN_TIME <= 0;

if (!defined &{"UNIVERSAL::BLESS"}) {
    eval 'sub UNIVERSAL::BLESS { ref($_[0])? () : CORE::bless($_[1],$_[0]) }';
    die if $@;
}

1;
