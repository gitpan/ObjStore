# Copyright © 1997-1998 Joshua Nathaniel Pritikin.  All rights reserved.
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
	    $COMPILE_TIME $TRANSACTION_PRIORITY
	    $FATAL_EXCEPTIONS $MAX_RETRIES $CLASS_AUTO_LOAD);

$VERSION = '1.22';

require Exporter;
require DynaLoader;
@ISA = qw(Exporter DynaLoader);
{
    my @x_adv = qw(&blessed &reftype
		   &translate &set_default_open_mode
		   &get_all_servers &get_lock_status 
		   &is_lock_contention &peek);
    my @x_tra = qw(&set_transaction_priority &schema_dir
		   &fatal_exceptions &release_name
		   &release_major &release_minor &release_maintenance
		   &network_servers_available 
		   &get_max_retries &set_max_retries
		   &get_page_size &return_all_pages 
		   &get_readlock_timeout &get_writelock_timeout
		   &set_readlock_timeout &set_writelock_timeout
		   &abort_in_progress &get_n_databases &set_stargate
		   &DEFAULT_STARGATE &PoweredByOS);
    my @x_old = qw();
    my @x_priv= qw($DEFAULT_OPEN_MODE %CLASSLOAD $CLASSLOAD $EXCEPTION
		   &_PRIVATE_ROOT);

    @EXPORT      = qw(&bless &begin
		      &try_read &try_abort_only &try_update);
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

# private root keys: qw(BRAHMA INC database_blessed_to layouts)
#  depreciated keys: qw(Brahma) 1.19

$TRANSACTION_PRIORITY = 0x8000;
sub set_transaction_priority {
    my ($pri) = @_;
    $TRANSACTION_PRIORITY = $pri;
    _set_transaction_priority($pri);
}

sub schema_dir() {
    carp "schema_dir is depreciated.  Instead use ObjStore::Config";
    require ObjStore::Config;
    &ObjStore::Config::SCHEMA_DBDIR;
}

sub PoweredByOS {
    use Config;
    "$Config{sitelib}/ObjStore/PoweredByOS.gif";
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

$FATAL_EXCEPTIONS = 1;   #happy default for newbie or my co-workers
sub fatal_exceptions {
    my ($yes) = @_;
    $FATAL_EXCEPTIONS = $yes;
}
*rethrow_exceptions = \&fatal_exceptions;

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

# For speed, you may assume that ONLY TRANSIENT data will be
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
# Once CORE::GLOBAL works -
#   *CORE::GLOBAL::bless = \&bless;

#sub BLESS {
#    my ($r1,$r2);
#    if (ref $r1) { warn "$r1 leaving ".ref $r1." for a new life in $r2";  }
#    else         { warn "$r2 entering $r1"; }
#    $r1->SUPER::BLESS($r2);
#}

# This is allowed to be expensive: it is only called once per class!
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

package UNLOADED;
package ObjStore;

sub mark_unloaded {
    # Is there a trick to undo the damage if finally loaded? XXX
    no strict;
    my $class = shift;
    warn "[marking $class as UNLOADED]\n" if $ObjStore::REGRESS;
    push(@{"${class}::ISA"}, 'UNLOADED');
    eval "package $class; ".' sub AUTOLOAD {
Carp::croak(qq[Sorry, "$AUTOLOAD" is not loaded.  You may need to adjust \@INC in order for your support code to be automatically loaded when the database is opened.\n]);
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
*ObjStore::disable_class_auto_loading = \&disable_auto_class_loading; #silly me

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

# 'bless' for databases is totally, completely, and utterly
# special-cased.  It's like stuffing a balloon inside itself.
package ObjStore::Database;
use Carp;
use vars qw(@OPEN0 @OPEN1);

@OPEN0=(sub { shift->sync_INC() });
@OPEN1=();

sub BLESS_ROOT { 'database_blessed_to' }  #root XXX

sub of {
    carp "ObjStore::Database::of() is depreciated: use the database_of method";
    $_[0]->database_of()
}
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

sub is_open_mvcc {
    my ($db) = @_;
    carp "is_open_mvcc is unnecessary; simply use is_open";
    $db->is_open eq 'mvcc';
}

sub is_open_read_only {
    my ($db) = @_;
    $db->is_open eq 'read' or $db->is_open eq 'mvcc';
}

sub _get_private_root {
    my ($db) = @_;
    my $rt = $db->_PRIVATE_ROOT();
    return if !$rt;
    my $priv = $rt->get_value;
    if (!$priv) {
	$priv = ObjStore::HV->new($db, 30);
	$rt->set_value($priv);
    }
    $priv;
}

sub get_INC {
    my ($db) = @_;
    my $priv = $db->_get_private_root;
    if (&ObjStore::Transaction::get_current()->get_type() ne 'read') {
	$priv->{INC} ||= [];
    }
    ($priv and exists $priv->{INC})? $priv->{INC} : undef;
}

sub sync_INC {
    my ($db) = @_;
    my $inc = $db->get_INC();
    return if !$inc;
    # optimize with a hash XXX
    for (my $x=0; $x < $inc->_count; $x++) {
	my $dir = $inc->[$x];
	my $ok=0;
	for (@INC) { $ok=1 if $_ eq $dir }
	if (!$ok) {
#	    warn "sync_INC: adding $dir";
	    push @INC, $dir;
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
	if (!ref $bs) {
	    #depreciated 1.19
	} else { $bs = $bs->[1]; }
	&ObjStore::safe_require('ObjStore::Database', $bs);

	# Must use CORE::bless here because it must be fully transparent.
	CORE::bless($db, $bs);
    }
    $db;
}

sub _blessto_slot {
    my ($db) = @_;
    my $priv = $db->_get_private_root;
    return if !$priv;
    $priv->{&BLESS_ROOT};
}

sub isa {
    my ($db, $class) = @_;
    return $db->SUPER::isa($class) if !ref $db;
    &ObjStore::begin(sub {
	my $bs = $db->_blessto_slot;
	return 0 if !$bs;
	return 1 if $class eq $bs->[1];
	&ObjStore::UNIVERSAL::_isa($class, $bs->[3]);
    });
}

# Even though the transient blessing doesn't match, the persistent
# blessing might be correct.  We need to check before doing a super
# slow update transaction.

# There are potentially four blessings to be aware of:
# 1. the current bless-to
# 2. the destination bless-to
# 3. the database bless-info
# 4. the per-class bless-info in BRAHMA

# figure out how to import stuff from ObjStore::UNIVERSAL XXX
sub BLESS {
    if (ref $_[0]) {
	my ($r, $class) = @_;
	croak "Cannot bless $r into non-ObjStore::Database class '$class'"
	    if !$class->isa('ObjStore::Database');
	return $r->SUPER::BLESS($class);
    }
    my ($class, $db) = @_;
    my $ok=0;
    &ObjStore::begin(sub {
	my $priv = $db->_get_private_root;
	return if !$priv;
	my $bs = $priv->{&BLESS_ROOT};
	return if !$bs;
	return if !ref $bs; #depreciated 1.19

	$ok=1 if
	    &ObjStore::blessed($db) ne $bs->[1] &&
		$bs->[1] eq $class &&
		    $bs->[2] <= ($ObjStore::UNIVERSAL::BLESS_VERSION{$class} || 0)
    });
    die if $@;
    my $ct = ObjStore::Transaction::get_current();
    if (!$ok and
	!$db->is_open_read_only and (!$ct or $ct->get_type ne 'read') and
	!$class->isa('UNLOADED')) {
	
	# This can be slow because it doesn't happen often.
	&ObjStore::begin('update', sub {
	    my $priv = $db->_get_private_root;
	    my $brah = ($priv->{BRAHMA} ||= ObjStore::HV->new($db, 30));
	    my $bs = $brah->{$class} ||= ObjStore::UNIVERSAL::_bless_info($class,$ObjStore::COMPILE_TIME);
	    if (!ObjStore::UNIVERSAL::_isa_tree_matches($class, $bs->[3])) {
		$bs = $brah->{$class} = ObjStore::UNIVERSAL::_bless_info($class,time);
	    }
	    $ObjStore::UNIVERSAL::BLESS_VERSION{$class} = $bs->[2];
	    $priv->{&BLESS_ROOT} = $bs;
	});
	die if $@;
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

*is_corrupted = \&ObjStore::UNIVERSAL::is_corrupted; #usual hack

sub _is_corrupted {
    my ($db, $v) = @_;
    warn "$db->is_corrupted: checking...\n" if $v >= 3;
    my $err=0;
    for my $r ($db->get_all_roots()) {
	my $z = $r->get_value;
	$err += $z->is_corrupted($v);
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

sub newHV { carp 'depreciated'; new ObjStore::HV(@_); }
sub newTiedHV { carp 'depreciated'; new ObjStore::HV(@_); }
sub newSack { carp 'depreciated'; new ObjStore::Set(@_); }

sub get_n_databases {
    carp "ObjStore::Database::get_n_databases depreciated; use ObjStore::get_n_databases";
    ObjStore::get_n_databases();
}

package ObjStore::Database::HV;
sub new { die "ObjStore::Database::HV has been renamed to ObjStore::HV::Database" }
sub BLESS {
    return $_[0]->SUPER::BLESS($_[1]) if ref $_[0];
    my ($class, $db) = @_;
    $class = 'ObjStore::HV::Database';
    $class->SUPER::BLESS($db);
}

package ObjStore::Segment;
use Carp;

sub of {
    carp "ObjStore::Segment::of() is depreciated: use the segment_of method";
    $_[0]->segment_of()
}
sub segment_of { $_[0]; }
sub database_of { $_[0]->_database_of->import_blessing; }

sub BLESS { croak "Segments absolutely cannot be re-blessed!" }

sub newHV { carp 'depreciated'; new ObjStore::HV(@_); }
sub newTiedHV { carp 'depreciated'; new ObjStore::HV(@_); }
sub newSack { carp 'depreciated'; new ObjStore::Set(@_); }

sub destroy {
    my ($o) = @_;
    if (!$o->is_empty()) { croak("attempt to destroy unempty os_segment"); }
    $o->_destroy;
}

package ObjStore::UNIVERSAL;
use Carp;
use vars qw(%BLESS_VERSION);
use overload ('""' => \&_pstringify,
	      'bool' => sub {1},
	      '==' => \&_peq,
	      '!=' => \&_pneq,
	     );

sub set_readonly { carp "set_readonly depreciated"; shift->const }

sub database_of { $_[0]->_database_of->import_blessing; }

# adapted from Devel::Symdump
sub _isa_tree {
    my ($pkg, $depth) = @_;
    $depth ||= 0;
    ++ $depth;
    if ($depth > 100) {warn "Deep recursion searching \@$pkg\::ISA\n"; return}
    my @isa;
    no strict 'refs';
    for my $z (@{"$pkg\::ISA"}) { push(@isa, $z, _isa_tree($z, $depth)); }
    \@isa;
}

sub _isa_tree_matches {
    my ($pkg, $isa, $depth) = @_;
    $depth ||= 0;
    ++ $depth;
    if ($depth > 100) {warn "Deep recursion searching \@$pkg\::ISA\n"; return}
    no strict 'refs';
    my $x=0;
    for my $z (@{"$pkg\::ISA"}) {
	return 0 if (!$isa->[$x] or $isa->[$x] ne $z or
		     !_isa_tree_matches($z, $isa->[$x+1], $depth));
	$x+=2;
    }
    return 0 if $isa->[$x+1];
    1;
}

sub _bless_info {
    my ($class, $when) = @_;
    $BLESS_VERSION{$class} = $when;
    # Can't use AVHV because AVHV uses bless.
    [0, $class, $when, _isa_tree($class)];
}

# insure(transient VERSION >= persistent VERSION)
# (transient side must drive evolution, yes?)
sub BLESS {
    if (ref $_[0]) {
	my ($r, $class) = @_;
	croak "Cannot bless $r into transient class '$class'"
	    if !$class->isa('ObjStore::UNIVERSAL');
	$r->SUPER::BLESS($class);
    }
    my ($class, $r) = @_;
    if (_is_persistent($r) and !$class->isa('UNLOADED')) {
	my $db = $r->database_of;
	my $priv = $db->_get_private_root;
	my $brah = ($priv->{BRAHMA} ||= new ObjStore::HV($db, 30));
	my $bs = ($brah->{$class} ||= _bless_info($class,$ObjStore::COMPILE_TIME));
	# Be suspicious if bless-to is not going to change.
	if (ObjStore::blessed($r) eq $class or
	    $bs->[2] > ($BLESS_VERSION{$class} || 0)) {
	    if (!_isa_tree_matches($class, $bs->[3])) {
		$bs = $brah->{$class} = _bless_info($class, time);
	    }
	}
	$BLESS_VERSION{$class} = $bs->[2];
	$r->_blessto_slot($bs);
    }
    $class->SUPER::BLESS($r);
}

sub _isa {
    my ($class, $isa, $depth) = @_;
    $depth ||= 0;

    ++ $depth;
    confess "ObjStore::UNIVERSAL::_isa: loop in \@ISA" if $depth > 100;
    for (my $x=0; $x < $isa->_count; $x++) {
	my $z = $isa->[$x];
	if (ref $z) { return 1 if _isa($class, $z, $depth); }
	else { return 1 if $class eq $z; }
    }
    0;
}

sub isa {
    my ($ref, $class) = @_;
    return $ref->SUPER::isa($class) if !ref $ref;
    my $bs = $ref->_blessto_slot;
    return $ref->SUPER::isa($class) if !$bs;
    return 1 if $class eq $bs->[1];
    _isa($class, $bs->[3]);
}

#shallow copy
sub clone_to { croak($_[0]."->clone_to(where) unimplemented") }

sub set_weak_refcnt_to_zero { croak "set_weak_refcnt_to_zero is unnecessary"; }

# Do fancy argument parsing to make it creating unsafe
# references a very intentional endevor.
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

sub is_evolved {1}
sub evolve {}

sub is_corrupted {
    my ($o, $vlev) = @_;
    $vlev = 'all' if !defined $vlev;
    if ($vlev !~ m/^\d+$/) {
	if ($vlev eq 'quiet') { $vlev = 0; }
	elsif ($vlev eq 'err') { $vlev = 1; }
	elsif ($vlev eq 'warn') { $vlev = 2; }
	elsif ($vlev eq 'info') { $vlev = 3; }
	elsif ($vlev eq 'all') { $vlev = 4; }
	else { croak("is_corrupted($vlev): unrecognized verbosity"); }
    }

    my $err=0;
    if ($o->can('_is_corrupted')) {
	$err += $o->_is_corrupted($vlev);
    } else {
	warn "$o->is_corrupted: no _is_corrupted method found\n" if $vlev >= 2;
    }
    $err;
}

package ObjStore::Ref;
use vars qw(@ISA);
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
	    $o->peek_any($at);
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
use vars qw(@ISA);
@ISA = qw(ObjStore::UNIVERSAL);

sub count { $_[0]->focus->_count; }

sub clone_to {
    my ($r, $seg, $cloner) = @_;
    $cloner->($r->focus)->new_cursor($seg);
}

package ObjStore::Container;
use vars qw(@ISA);
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
use vars qw(@ISA %REP);
@ISA=qw(ObjStore::Container);

sub _is_corrupted {
    my ($o, $vlev) = @_;
    warn "$o->is_corrupted: checking...\n" if $vlev >= 3;
    my $err=0;
    for (my $z=0; $z < $o->_count; $z++) {
	my $e = $o->[$z];
	$err += $e->is_corrupted($vlev) if ObjStore::blessed($e);
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
use vars qw(@ISA %REP);
@ISA=qw(ObjStore::Container);

sub _is_corrupted {
    my ($o, $vlev) = @_;
    warn "$o->is_corrupted: checking...\n" if $vlev >= 3;
    my $err=0;
    while (my($k,$v) = each %$o) {
	$err += $v->is_corrupted($vlev) if ObjStore::blessed($v);
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
use vars qw(@ISA %REP);
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

sub _is_corrupted {0}  #write your own!

package ObjStore::Set;
use base 'ObjStore::HV';
use Carp;

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
$COMPILE_TIME = time;
die "COMPILE_TIME must be positive" if $COMPILE_TIME < 0;

package UNIVERSAL;

if (!defined &{"UNIVERSAL::BLESS"}) {
    eval 'sub BLESS { ref($_[0])? () : CORE::bless($_[1],$_[0]) }';
    die if $@;
}

1;
