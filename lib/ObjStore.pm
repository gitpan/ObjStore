# Copyright © 1997-1998 Joshua Nathaniel Pritikin.  All rights reserved.
#
# This package is free software and is provided "as is" without express
# or implied warranty.  It may be used, redistributed and/or modified
# under the terms of the Perl Artistic License (see
# http://www.perl.com/perl/misc/Artistic.html)

package ObjStore;
require 5.004;
use strict;
use Carp;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK @EXPORT_FAIL %EXPORT_TAGS
	    $DEFAULT_OPEN_MODE $EXCEPTION %CLASSLOAD $CLASSLOAD
	    $RUN_TIME $TRANSACTION_PRIORITY
	    $FATAL_EXCEPTIONS $MAX_RETRIES $CLASS_AUTO_LOAD);

$VERSION = '1.24';

require Exporter;
require DynaLoader;
@ISA = qw(Exporter DynaLoader);
{
    my @x_adv = qw(&peek &blessed &reftype &os_version &translate 
		   &subscribe &unsubscribe &get_all_servers 
		   &set_default_open_mode
		   &get_lock_status &is_lock_contention 
		  );
    my @x_tra = (qw(&fatal_exceptions &release_name
		    &network_servers_available &set_transaction_priority
		    &get_max_retries &set_max_retries
		    &get_page_size &return_all_pages 
		    &get_readlock_timeout &get_writelock_timeout
		    &set_readlock_timeout &set_writelock_timeout
		    &abort_in_progress &get_n_databases
		    &set_stargate &DEFAULT_STARGATE
		    &PoweredByOS),
		 # depreciated
		 qw(&release_major &release_minor &release_maintenance
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
    my $reason = shift;
    $reason = ObjStore::Transaction::SEGV_reason() if $reason eq 'SEGV';
    $reason ||= 'SEGV';
    local $Carp::CarpLevel += 1;
    confess "ObjectStore: $reason\t";
};

$SIG{SEGV} = \&$EXCEPTION
    unless defined $SIG{SEGV}; # MUST NOT BE CHANGED! XXX

eval { require Thread::Specific; };
undef $@;
bootstrap ObjStore($VERSION,
		   'Thread::Specific'->can('key_create')?
		   'Thread::Specific'->key_create() : 0);

warn "You need at least ObjectStore 4.0.1!  How did you get this extension compiled?\n" if ObjStore::os_version() < 4.0001;

require ObjStore::GENERIC;
require ObjStore::REP::FatTree;

sub export_fail {
    shift;
    if ($_[0] eq 'PANIC') { ObjStore::debug(shift); }
    @_;
}

# keywords flying coach...
sub reftype ($);
sub blessed ($);
sub bless ($;$);

$TRANSACTION_PRIORITY = 0x8000; #tied scalar? XXX
sub set_transaction_priority {
    my ($pri) = @_;
    $TRANSACTION_PRIORITY = $pri;
    _set_transaction_priority($pri);
}

sub PoweredByOS {
    use Config;
    warn "PoweredByOS wont work until Makefile.PL is fixed.  Sorry";
    "$Config{sitelib}/ObjStore/PoweredByOS.gif";
}

$FATAL_EXCEPTIONS = 1;   #happy default for newbies... or my co-workers!
sub fatal_exceptions {
    my ($yes) = @_;
    $FATAL_EXCEPTIONS = $yes;
}

$MAX_RETRIES = 10;
sub get_max_retries { $MAX_RETRIES; }
sub set_max_retries { $MAX_RETRIES = $_[0]; }

sub begin {
    my ($tt, $code);
    my $ctt;
    {
	my $ctx = ObjStore::Transaction::get_current();
	$ctt = $ctx->get_type if $ctx;
    }
    if (@_ == 1) {
	$tt = $ctt || 'read';
	$code = shift;
    } elsif (@_ == 2) {
	($tt, $code) = @_;
    } else {
	croak "begin([type], code)";
    }

    my $wantarray = wantarray;
    my @result;
    my $result;
    my $retries = 0;
    my $do_retry;
    do {
	$result=undef;
	@result=();
	undef $@;
	my $txn = ObjStore::Transaction::new($tt);
	my $ok=0;
	$ok = eval {
	    if ($wantarray) {
		@result = $code->();
	    } elsif (defined $wantarray) {
		$result = $code->();
	    } else {
		$code->();
	    }
	    $txn->post_transaction(); #1
	    1;
	};
	warn $@ if ($@ && $ObjStore::REGRESS);
	($ok and $tt !~ m'^abort') ? $txn->commit() : $txn->abort();
	$txn->post_transaction(); #2
	++ $retries;
	$do_retry = ($txn->deadlocked && $txn->top_level &&
		     $retries < get_max_retries());
	$txn->destroy;
	die if ($@ and $FATAL_EXCEPTIONS and !$do_retry);

    } while ($do_retry);
    if (!defined wantarray) { () } else { wantarray ? @result : $result; }
}

# For speed, you may assume that ONLY TRANSIENT DATA will be
# transferred through the stargate.

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
    my @c = split(m/\:\:/, $class);
    while (!@{"$class\::ISA"} and @c) {
	my $file = join('/',@c).".pm";
	local $@;
	eval { require $file }; #can't use 'begin' - too complicated
#	warn "$file: ".($@?$@:"ok")."\n";
	if ($@) {
	    if ($@ !~ m"Can't locate .*? in \@INC") { die $@ }
#	    else { warn $@ }
#	    undef $@;
	}
	# Can't loop.  Too dangerous.
#	pop @c;
	last;
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
	/^refcnt/ and $mask |= 1, next;
	/^assign/ and $mask |= 2, next;
	/^bridge/ and $mask |= 4, next;
	/^array/  and $mask |= 8, next;
	/^hash/   and $mask |= 16, next;
	/^set/    and $mask |= 32, next;
	/^cursor/ and $mask |= 64, next;
	/^bless/  and $mask |= 128, next;
	/^root/   and $mask |= 256, next;
	/^splash/ and $mask |= 512, next;
	/^txn/    and $mask |= 1024, next;
	/^ref/    and $mask |= 2048, next;
	/^wrap/   and $mask |= 4096, next;
	/^thread/ and $mask |= 8192, next;
	/^index/  and $mask |= 16384, next;
	/^PANIC/  and $mask = 0xffff, next;
	die "Snawgrev $_ tsanik breuzwah dork'ni";
    }
    if ($mask) {
	Carp->import('verbose');
    }
    $ObjStore::REGRESS = $mask != 0;
    _debug($mask);
}

#------ ------ ------ ------
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

# Psuedo-class to animate persistent bless!  (Kudos to Devel::Symdump!)
#
package ObjStore::BRAHMA;
use Carp;
use vars qw(@ISA @EXPORT %CLASS_DOGTAG);
BEGIN {
    @ISA = qw(Exporter);
    @EXPORT = (qw(&_isa &_versionof &_is_evolved &iscorrupt &GLOBS
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
sub GLOBS {
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
    for (my $x=0; $x < $isa->_count; $x++) {
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
	for (my ($c,$v) = each %$then) {
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
    if (!defined $ {"$pkg\::VERSION"}) {
	warn "\$$pkg\::VERSION must be assigned a version string!\n";
    } else {
	$vmap->{$pkg} = $ {"$pkg\::VERSION"};
    }
    for my $z (@{"$pkg\::ISA"}) { isa_versions($z, $vmap, $depth); }
    $vmap;
}

sub _engineer_blessing {
    my ($br, $bs, $o, $toclass) = @_;
    if (! $bs) {
	confess "ObjStore::BRAHMA must be notified of run-time manipulation of VERSION strings by changing \$ObjStore::RUN_TIME to be != \$CLASS_DOGTAG{$toclass}" 
	    if ($CLASS_DOGTAG{$toclass} or 0) == $ObjStore::RUN_TIME; #majify? XXX

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

    # Acquiring a lock here messes up the deadlock regression test.
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

sub is_open_read_only {
    my ($db) = @_;
    $db->is_open eq 'read' or $db->is_open eq 'mvcc';
}

'ObjStore::Database'->_register_private_root_key('INC');

sub get_INC { shift->_private_root_data('INC', sub { [] }); }
sub sync_INC {
    my ($db) = @_;
    my $inc = $db->_private_root_data('INC');
    return if !$inc;
    # optimize with a hash XXX
    for (my $x=0; $x < $inc->_count; $x++) {
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

	# Must use CORE::bless here: this is strictly an import.
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
	if ($bs->[1] eq $class) {
	    # Already blessed and certified: way cool dude!
	    $need_rebless = 0;
	}
    });
    die if $@;
    no strict 'refs';
    if ($need_rebless and
	!$ {"$class\::UNLOADED"} and
	!$db->is_open_read_only) {

	my $ct = ObjStore::Transaction::get_current();
	if (!$ct or $ct->get_type ne 'read') {
	    &ObjStore::begin('update', sub {
		 my $br = $db->_conjure_brahma;
		 _engineer_blessing($br, scalar(_get_certified_blessing($br, $db, $class)), $db, $class);
	    });
	    die if $@;
	}
    }
    $class->SUPER::BLESS($db);
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
    $o->_destroy if $empty;  #secret destroy method :-)
}

sub root {
    my ($o, $roottag, $nval) = @_;
    my $root = $o->find_root($roottag);
    if (defined $nval and
	&ObjStore::Transaction::get_current()->get_type() ne 'read') {
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
	my $s = $db->create_segment;
	$s->set_comment("_osperl_private");
	$priv = 'ObjStore::HV'->new($s, 30);
	$rt->set_value($priv);
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
	if (!$d and $_ROOT_KEYS{$key}->{mk}) {
	    $d = $priv->{$key} = $_ROOT_KEYS{$key}->{mk}->($priv)
	}
	$d;
    }
}

#------- ------- ------- -------
sub is_open_mvcc {
    my ($db) = @_;
    carp "is_open_mvcc is unnecessary; simply use is_open";
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

sub BLESS { croak "Segments absolutely cannot be blessed (you segment head!)" }

sub destroy {
    my ($o) = @_;
    if (!$o->is_empty()) {
	croak("Attempt to destroy unempty os_segment!  You may use osp_hack if you really need to do this");
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
	     );

sub database_of { $_[0]->_database_of->import_blessing; }

sub BLESS {
    if (ref $_[0]) {
	my ($r, $class) = @_;
	croak "Cannot bless $r into transient class '$class'"
	    if !$class->isa('ObjStore::UNIVERSAL');
	$r->SUPER::BLESS($class);
    }
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
    $seg = ObjStore::Segment::get_transient_segment()
	if !defined $seg || (!ref $seg and $seg eq 'transient');
    my $type;
    if (!defined $safe or $safe eq 'safe') { $type=0; }
    elsif ($safe eq 'unsafe' or $safe eq 'hard') { $type=1; }
    else { croak("$o->new_ref($safe,...): unknown type"); }
    $o->_new_ref($type, $seg->segment_of);
}

sub evolve {
    # Might be as simple as this:  bless $_[0], ref($_[0]);
    # but you have to code it!
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

sub count { $_[0]->focus->_count; }

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
    $class->new($where, $o->_count() || 1);
}

sub count { shift->_count; }  #goofy XXX

package ObjStore::AV;
use vars qw($VERSION @ISA %REP);
$VERSION = '1.00';
@ISA=qw(ObjStore::Container);

sub _iscorrupt {
    my ($o, $vlev) = @_;
    warn "$o->iscorrupt: checking...\n" if $vlev >= 3;
    my $err=0;
    for (my $z=0; $z < $o->_count; $z++) {
	my $e = $o->[$z];
	$err += $e->iscorrupt($vlev) if ObjStore::blessed($e);
    }
    $err;
}

sub map {
    my ($o, $sub) = @_;
    my @r;
    for (my $x=0; $x < $o->_count; $x++) { push(@r, $sub->($o->[$x])); }
    @r;
}

package ObjStore::HV;
use Carp;
use vars qw($VERSION @ISA %REP);
$VERSION = '1.00';
@ISA=qw(ObjStore::Container);

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

package ObjStore::Index;
use Carp;
use vars qw($VERSION @ISA %REP);
$VERSION = '1.00';
@ISA='ObjStore::Container';

sub new {
    my ($this, $loc, @CONF) = @_;
    $loc = $loc->segment_of;
    my $class = ref($this) || $this;
    my $x = ObjStore::REP::FatTree::Index::new($class, $loc);
    $x->configure(@CONF) if @CONF;
    $x;
}

sub map {
    my ($o, $sub) = @_;
    my @r;
    for (my $x=0; $x < $o->_count; $x++) { push(@r, $sub->($o->[$x])); }
    @r;
}

sub POSH_PEEK {
    my ($val, $o, $name) = @_;
    $o->{coverage} += $val->_count;
    my $big = $val->_count > $o->{width};
    my $limit = $big? $o->{summary_width} : $val->_count;

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

package ObjStore::Database::HV;
sub new { die "ObjStore::Database::HV has been renamed to ObjStore::HV::Database" }
sub BLESS {
    return $_[0]->SUPER::BLESS($_[1]) if ref $_[0];
    my ($class, $db) = @_;
    $class = 'ObjStore::HV::Database';
    $class->SUPER::BLESS($db);
}

package ObjStore::Set;
use Carp;
use base 'ObjStore::HV';
use vars qw($VERSION);
$VERSION = 'You suck!';

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

package UNIVERSAL;

if (!defined &{"UNIVERSAL::BLESS"}) {
    eval 'sub BLESS { ref($_[0])? () : CORE::bless($_[1],$_[0]) }';
    die if $@;
}
if (!defined &{"UNIVERSAL::versionof"}) {
    eval 'sub versionof { no strict "refs"; $ {"$_[1]::VERSION"} }';
    die if $@;
}

1;
