# Copyright (c) 1997 Joshua Nathaniel Pritikin.  All rights reserved.
# This package is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.
package ObjStore;
require 5.004;
use strict;
use Carp;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS
	    $DEFAULT_OPEN_MODE $EXCEPTION %CLASSLOAD $CLASSLOAD
	    $COMPILE_TIME $TRANSACTION_PRIORITY $RETHROW_ERRORS
	    $MAX_RETRIES);

$VERSION = '1.19';  #is a string, not a number!

require Exporter;
require DynaLoader;
@ISA         = qw(Exporter DynaLoader);
@EXPORT      = qw(&bless &try_read &try_abort_only &try_update);
{
    my @x_adv = qw(&begin &translate &set_default_open_mode
		   &set_stargate &get_all_servers
		   &database_of &segment_of &get_lock_status
		   &is_lock_contention &peek);
    my @x_tra = qw(&set_transaction_priority &schema_dir
		   &reftype &rethrow_exceptions &release_name
		   &release_major &release_minor &release_maintenance
		   &network_servers_available 
		   &get_max_retries &set_max_retries
		   &get_page_size &return_all_pages 
		   &get_readlock_timeout &get_writelock_timeout
		   &set_readlock_timeout &set_writelock_timeout
		   &abort_in_progress &get_n_databases
		   &DEFAULT_STARGATE &PoweredByOS);
    my @x_old = qw(&stargate);
    my @x_priv= qw($DEFAULT_OPEN_MODE %CLASSLOAD $CLASSLOAD $EXCEPTION
		   &_PRIVATE_ROOT);

    %EXPORT_TAGS = (ADV => [@EXPORT, @x_adv],
		    ALL => [@EXPORT, @x_adv, @x_tra]);

    @EXPORT_OK   = (@EXPORT, @x_adv, @x_tra, @x_old, @x_priv);
}

$EXCEPTION = sub {
    my $reason = shift;
    $reason = ObjStore::Transaction::SEGV_reason() if $reason eq 'SEGV';
    $reason ||= "SEGV";
    local($Carp::CarpLevel) += 2;
    my $skip = "[Skip $Carp::CarpLevel] "; #XXX
    confess "ObjectStore: $reason\t";
};
$SIG{SEGV} = \&$EXCEPTION; # DO NOT CHANGE

bootstrap ObjStore $VERSION;
require ObjStore::GENERIC;

# keywords flying coach...
sub reftype ($);
sub blessed ($);
sub bless ($;$);

sub set_transaction_priority {
    my ($pri) = @_;
    $TRANSACTION_PRIORITY = $pri;
    _set_transaction_priority($pri);
}

sub schema_dir() {
    require ObjStore::Config;
    &ObjStore::Config::SCHEMA_DBDIR;
}

sub PoweredByOS {
    use Config;
    "$Config{sitelib}/ObjStore/PoweredByOS.gif";
}

sub try_read(&) { ObjStore::begin('read', $_[0]); }
sub try_update(&) { ObjStore::begin('update', $_[0]); }
sub try_abort_only(&) { ObjStore::begin('abort_only', $_[0]); }

# deal with wantarray XXX

$RETHROW_ERRORS = 1;
sub rethrow_exceptions {
    my ($yes) = @_;
    $RETHROW_ERRORS = $yes;
}

$MAX_RETRIES = 10;
sub get_max_retries { $MAX_RETRIES; }
sub set_max_retries { $MAX_RETRIES = $_[0]; }

sub begin($&) {
    croak "begin(ttype, coderef)" if @_ != 2;
    my ($tt, $code) = @_;
    my $retries = 0;
    my $do_retry;
    do {
	my $txn = ObjStore::Transaction::new($tt);
	my $ok=0;
	$ok = eval {
	    $code->();
	    $txn->post_transaction();
	    1;
	};
	($ok and $tt !~ m'^abort') ? $txn->commit() : $txn->abort();
	$txn->post_transaction();
	++ $retries;
	$do_retry = ($txn->deadlocked && $txn->top_level &&
		     $retries < get_max_retries());
	$txn->destroy;
	die if ($@ and $RETHROW_ERRORS and !$do_retry);

    } while ($do_retry);
    ()
}

sub DEFAULT_STARGATE {
    my ($seg, $sv) = @_;
    my $type = reftype $sv;
    my $class = ref $sv;
#    croak("$sv already persistent") if $class->isa('ObjStore::UNIVERSAL');
    if ($type eq 'REF') {
	my $sv = $$sv;
	$sv->new_ref($seg);
    } elsif ($type eq 'HASH') {
	my $hv = new ObjStore::HV($seg);
	while (my($hk,$v) = each %$sv) { $hv->STORE($hk, $v); }
	%$sv = ();
	if ($class ne 'HASH') { ObjStore::bless $hv, $class; }
	$hv
    } elsif ($type eq 'ARRAY') {
	my $av = new ObjStore::AV($seg, scalar(@$sv) || 7);
	for (my $x=0; $x < @$sv; $x++) { $av->STORE($x, $sv->[$x]); }
	@$sv = ();
	if ($class ne 'ARRAY') { ObjStore::bless $av, $class; }
	$av
    } else {
	croak("ObjStore::DEFAULT_STARGATE: Don't know how to translate $sv");
    }
};

set_stargate(\&DEFAULT_STARGATE);
sub gateway { carp 'depreciated; call set_stargate instead'; set_stargate(@_); }
sub set_gateway { carp 'depreciated; call set_stargate instead'; set_stargate(@_); }

# the revised new standard bless limited edition
sub bless ($;$) {
    my ($ref, $class) = @_;
    $class ||= scalar(caller);
    my $old = blessed $ref;
    return $ref if ($old || '') eq $class;
    $ref->LEAVE_FOR($class) if $old;
    $class->ABSORB($ref);
}

# This is allowed to be expensive.  It is only called once per class.
sub require_isa_tree {
    no strict 'refs';
    my ($class) = @_;

#    warn "require $class";
    my $file = $class;
    $file =~ s|::|/|g;
    $file .= ".pm";
    
    eval { require $file };  #XXX eval might explode
    die $@ if ($@ and $@ !~ m"Can't locate $file in \@INC");  #correct? XXX

    if (defined @{"$class\::ISA"}) {
	for my $c (@{"$class\::ISA"}) { require_isa_tree($c) }
    }
}

$CLASSLOAD = sub {
    no strict 'refs';
    my ($db, $base, $class) = @_;

    # We can check @ISA because all persistent classes should have it.
    unless (defined @{"$class\::ISA"}) {
	require_isa_tree($class);
	undef $@;
	push(@{"${class}::ISA"}, $base) if @{"${class}::ISA"} == 0;
    }
    $class;
};

sub disable_auto_class_loading {
    $CLASSLOAD = sub {
	my ($db, $base, $class) = @_;
	$class;
    };
}
*ObjStore::disable_class_auto_loading = \&disable_auto_class_loading; #silly me

sub lookup {
    my ($path, $mode) = @_;
    $mode = 0666 if !defined $mode;
    my $db;
    $db = _lookup($path, $mode);
    $db->close if $db->is_open;   # Needed if database was created (bizarre!)
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
    $create_mode = 0666 if !defined $create_mode;
    my $db = lookup($path, $create_mode);
    return if !$db;
    $db->open($mode);
}

sub peek {
    croak "ObjStore::peek(top)" if @_ != 1;
    require ObjStore::Peeker;
    my $pk = new ObjStore::Peeker;
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
	/^PANIC/  and $mask = 0xffff, next;
	die "Snawgrev $_ tsanik breuzwah dork'ni";
    }
    _debug($mask);
}

sub database_of { $_[0]->database_of; }
sub segment_of { $_[0]->segment_of; }

sub FETCH_TRANSIENT_LAYOUT {  #rename? XXX
    my ($class) = @_;
    no strict 'refs';
    croak '\%{'.$class.'\::FIELDS} not found' if !defined %{"$class\::FIELDS"};
    my $fm = \%{"$class\::FIELDS"};
    $fm->{__VERSION__} ||= $ObjStore::COMPILE_TIME;
    $fm;
}

package ObjStore::Database;
use Carp;

sub BLESS_ROOT { 'database_blessed_to' }  #root XXX

sub of { $_[0]->database_of }
sub database_of { $_[0]; }
sub segment_of { $_[0]->get_default_segment; }

sub open {
    my ($db, $mode) = @_;
    $mode = $ObjStore::DEFAULT_OPEN_MODE if !defined $mode;
    if ($mode =~ /^\d$/) {
	if ($mode == 0)    { $mode = 'update' }
	elsif ($mode == 1) { $mode = 'read' }
	else { croak "ObjStore::open($db, $mode): mode $mode??" }
    }
    if ($mode eq 'mvcc') { $db->_open_mvcc; }
    else { $db->_open($mode eq 'read'); }

    # Acquiring a lock here messes up the deadlock regression test.
    if ($ObjStore::TRANSACTION_PRIORITY &&
	!ObjStore::Transaction::get_current()) {
	# allow programs to disable? XXX
	ObjStore::try_read(sub {
	    my $priv = $db->_get_private_root;
	    if ($priv and exists $priv->{&BLESS_ROOT}) {
		no strict 'refs';
		my $base = $priv->{&BLESS_ROOT};
		unless (defined %{"$base\::"}) {
		    my $file = $base;
		    $file =~ s,::,/,g;
		    require "$file.pm";
		}
		if ($base->isa('ObjStore::Database')) {
		    $base->SUPER::ABSORB($db);
		} else {
		    carp "$db cannot be blessed into $base since $base is not an ObjStore::Database";
		}
	    }
	    $db->verify_class_fields();
	});
	die if $@;
    }
    $db;
}

sub _get_private_root {
    my ($DB) = @_;
    my $rt = $DB->_PRIVATE_ROOT();
    return undef if !$rt;
    my $priv = $rt->get_value;
    if (!$priv) {
	$priv = ObjStore::HV->new($DB, 30);
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
    for (my $x=0; $x < $inc->_count; $x++) {
	my $dir = $inc->[$x];
	my $ok=0;
	for (@INC) { $ok=1 if $_ eq $dir }
	if (!$ok) {
#	    warn "adding $dir";
	    push @INC, $dir;
	}
    }
}

sub new {
    my $class = shift;
    my $db = ObjStore::open(@_);
    ObjStore::bless $db, $class;
}

sub LEAVE_FOR {
    my ($r, $class) = @_;
    croak "Cannot bless $r into non-ObjStore::Database class '$class'"
	if !$class->isa('ObjStore::Database');
    $r->SUPER::LEAVE_FOR($class);
}

sub ABSORB {
    my ($class, $db) = @_;
    # must be outside a transaction until we get nested txns
    my $ok=0;
    ObjStore::try_read(sub {
	my $priv = $db->_get_private_root;
	if ($priv and exists $priv->{&BLESS_ROOT}) {
	    $ok = $priv->{&BLESS_ROOT} eq $class;
	}
    });
    die if $@;
    # new bless...
    if (!$ok) {
	ObjStore::try_update(sub {
	    my $priv = $db->_get_private_root;
	    $priv->{&BLESS_ROOT} = $class;
	});
	die if $@;
    }
    $class->SUPER::ABSORB($db);
}

# This is called by most methods in ObjStore::Database::HV
sub gc_segments {
    my ($o) = @_;
    for my $s ($o->get_all_segments()) {
	$s->destroy if $s->is_empty();
    }
}

sub LAYOUTS { 'layouts' }  #root XXX

sub class_fields {
    my ($db, $class) = @_;
    my $priv = $db->_get_private_root;
    my $layouts = ($priv->{&LAYOUTS} ||= ObjStore::HV->new($db, 40));
    my $pfields = ($layouts->{$class} ||=
		   bless { __VERSION__ => 0 }, 'ObjStore::AVHV::Fields');

    my $fields = ObjStore::FETCH_TRANSIENT_LAYOUT($class);
    my $redo = ($pfields->{__CLASS__} or '') ne $class;

    if ($redo or $pfields->{__VERSION__} != $fields->{__VERSION__}) {

	if ($redo or !$pfields->is_compatible($fields)) {
	    use integer;
	    # stomp it but avoid sending $fields through the stargate
	    $pfields = $layouts->{$class} = bless({}, 'ObjStore::AVHV::Fields');
	    for my $k (keys %$fields) { $pfields->{$k} = $fields->{$k} }
	    $pfields->{__CLASS__} = $class;
	}
    }
    $pfields->{__VERSION__} = $fields->{__VERSION__};
    $pfields;
}

# insure(transient __VERSION__ >= persistent __VERSION__)
# e.g. transient side drives evolution (obvious yes?)
sub verify_class_fields {
    my ($db) = @_;
    return if $] < 5.00450;
    my $priv = $db->_get_private_root;
    return if (!$priv or !exists $priv->{&LAYOUTS});
    my $layouts = $priv->{&LAYOUTS};

    # for all class layouts
    while (my ($class, $pfields) = each %$layouts) {
	croak "Field map for $class is set to $pfields->{__CLASS__}" if
	    $pfields->{__CLASS__} ne $class;
	no strict 'refs';
	next if !defined %{"$class\::FIELDS"};
	my $fields = \%{"$class\::FIELDS"};
	if (!$pfields->is_compatible($fields)) {
	    if ($fields->{__VERSION__} <= $pfields->{__VERSION__}) {
		$fields->{__VERSION__} = $pfields->{__VERSION__}+1;
	    }
	}
    }
}

sub destroy {
    my ($o, $step) = @_;
    $step ||= 10;
    my $more;
    do {
	&ObjStore::try_update(sub {
	    my @r = ($o->get_all_roots, $o->_PRIVATE_ROOT);
	    for (my $x=0; $x < $step and @r; $x++) { (pop @r)->destroy }
	    $more = @r;
	});
	die if $@;
    } while ($more);

    # Other databases may still have references to data.  We can't safely
    # delete until there is definitely no data left.
    # This doesn't work if there have been references!  Help!  XXX
    my $empty=1;
    &ObjStore::try_update(sub {
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

# to store bless-to persistently
sub _get_persistent_raw_string {
    my ($db, $class) = @_;
    $class .= "\x0";		#null termination
    my $root = $db->_get_private_root;
    die "Can't fetch private root" if !$root;
    # root
    $root->{Brahma} = ObjStore::HV->new($db, 30) if !$root->{Brahma};
    my $bhava = $root->{Brahma};
    $bhava->{$class} = $class if !$bhava->{$class};
    $bhava->_get_raw_string($class);
}

sub peek {
    my ($val, $o) = @_;
    my $pr = $val->_PRIVATE_ROOT;
    my @priv = ($o->{all} and $pr)? $pr : ();
    for my $r ($val->get_all_roots, @priv) {
	$o->prefix;
	++$o->{level};
	my $name = $o->{addr}? "$r" : 'ObjStore::Root';
	$o->o("$name ",$r->get_name," = ");
	$o->{has_prefix}=1;
	$o->peek_any($r->get_value);
	--$o->{level};
	$o->nl;
	++ $o->{coverage};
    }
}

sub newHV { carp 'depreciated'; new ObjStore::HV(@_); }
sub newTiedHV { carp 'depreciated'; new ObjStore::HV(@_); }
sub newSack { carp 'depreciated'; new ObjStore::Set(@_); }

sub get_n_databases {
    carp "ObjStore::Database::get_n_databases depreciated; use ObjStore::get_n_databases";
    ObjStore::get_n_databases();
}

# Assume that tied-refs will become available shortly!  Merge back
# into ObjStore::Database?

package ObjStore::Database::HV;
use ObjStore;
use base 'ObjStore::Database';

sub ROOT() { 'hv' }

sub hash {
    my ($o) = @_;
    $o->root(&ROOT, sub {new ObjStore::HV($o, 25)} );
}

sub STORE {
    my ($o, $k, $v) = @_;
    my $t = $o->hash();
    $t->{$k} = $v;
    $o->gc_segments;
    defined wantarray? ($v) : ();
}

sub FETCH {
    my ($o, $k) = @_;
    my $t = $o->hash();
    $t->{$k};
}

sub DELETE {
    my ($o, $k) = @_;
    delete $o->hash()->{$k};
    $o->gc_segments;
}

package ObjStore::Segment;
#use overload ('""' => \&get_number,
#	      'bool' => sub {1});

sub of { $_[0]->segment_of }
sub segment_of { $_[0]; }

use Carp;
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
use overload ('""' => \&_pstringify,
	      'bool' => sub {1});

sub LEAVE_FOR {
    my ($r, $class) = @_;
    croak "Cannot bless $r into transient class '$class'"
	if !$class->isa('ObjStore::UNIVERSAL');
    $r->SUPER::LEAVE_FOR($class);
}

#shallow copy
sub clone_to { croak($_[0]."->clone_to(where) unimplemented") }

#called if refs=0 && weakrefs!=0
sub NOREFS {}

sub new_ref {
    my ($o, $seg) = @_;
    $seg ||= $o;
    $o->_new_ref($seg->segment_of);
}

package ObjStore::UNIVERSAL::Ref;
use vars qw(@ISA);
@ISA = qw(ObjStore::UNIVERSAL);

sub open {
    my ($r, $mode) = @_;
    my $db = $r->get_database;  #can throw exception :-(
    $db->open($mode) if !$db->is_open;
    die "Assertion failed: $r is broken" if $r->_broken;  #XXX
}

sub clone_to {
    my ($r, $seg, $cloner) = @_;
    $cloner->($r->focus)->new_ref($seg);
}

sub peek {
    my ($val, $o, $name) = @_;
    ++ $o->{coverage};
    $o->o("$name => ");
    $o->{has_prefix}=1;
    ++ $o->{level};
    my $at = $val->focus;
    $o->peek_any($at);
    -- $o->{level};
    $o->nl;
}

package ObjStore::UNIVERSAL::Cursor;
use vars qw(@ISA);
@ISA = qw(ObjStore::UNIVERSAL::Ref);

sub clone_to {
    my ($r, $seg, $cloner) = @_;
    $cloner->($r->focus)->new_cursor($seg);
}

package ObjStore::UNIVERSAL::Container;
use vars qw(@ISA);
@ISA = qw(ObjStore::UNIVERSAL);

sub new_cursor {
    my ($o, $seg) = @_;
    $seg ||= $o;
    $o->_new_cursor($seg->segment_of);
}

sub clone_to {
    my ($o, $where) = @_;
    my $class = ref($o) || $o;
    $class->new($where, $o->_count() || 1);
}

package ObjStore::AV;
use vars qw(@ISA %REP);
@ISA=qw(ObjStore::UNIVERSAL::Container);

package ObjStore::HV;
use vars qw(@ISA %REP);
@ISA=qw(ObjStore::UNIVERSAL::Container);

# move AVHV support to separate file?
package ObjStore::AVHV::Fields;
use vars qw(@ISA);
@ISA=qw(ObjStore::HV);

sub is_system_field {
    my ($o, $name) = @_;
    my $yes = ($name eq '__VERSION__' or
	       $name eq '__MAX__' or
	       $name eq '__CLASS__');
    $yes;
}

sub is_compatible {
    my ($pfields, $fields) = @_;
    my $yes=1;
    for my $k (keys %$fields) {
	next if $pfields->is_system_field($k);
	my $xx = $pfields->{$k} || -1;
	if ($xx != $fields->{$k}) { $yes=0; last }
    }
    $yes;
}

package ObjStore::AVHV;
use Carp;
use vars qw(@ISA);
@ISA=qw(ObjStore::AV);

sub new {
    require 5.00452;
    my ($class, $where, $init) = @_;
    $init ||= {};
    croak "$class->new(where, init)" if @_ < 2;
    my $fmap = $where->database_of->class_fields($class);
    my $o = $class->SUPER::new($where, $fmap->{__MAX__}+1);
    $o->[0] = $fmap;
    #do initialization? XXX
    while (my ($k,$v) = each %$init) {
	croak "Bad key '$k' for $fmap" if !exists $fmap->{$k};
	$o->{$k} = $v;
    }
    %$init = ();  # stargate convention
    $o;
}

sub is_evolved {
    my ($o) = @_;
    my $class = ref $o;
    my $fields = ObjStore::FETCH_TRANSIENT_LAYOUT($class);
    my $pfm = $o->[0];
    ($pfm->{__CLASS__} eq $class &&
     $pfm->{__VERSION__} == $fields->{__VERSION__});
}

sub evolve {
    require 5.00452;
    my ($o) = @_;
    my $class = ref $o;
    my $fields = ObjStore::FETCH_TRANSIENT_LAYOUT($class);
    my $pfields = $o->[0];

    if (! $pfields->is_compatible($fields)) {
	#copy interesting fields to @tmp
	my @tmp;
	while (my ($k,$v) = each %$pfields) {
	    next if $pfields->is_system_field($k);
	    push(@tmp, [$k,$o->[$v]]) if exists $fields->{$k};
	}

	#clear $o
	for (my $x=0; $x < $o->_count; $x++) { $o->[$x] = undef }

	#copy @tmp back using new schema
	for my $z (@tmp) { $o->[$fields->{$z->[0]}] = $z->[1]; }

	$o->[0] = $o->database_of->class_fields(ref $o);
    }
}

# Hash style, but in square brackets
sub peek {
    require 5.00452;
    my ($val, $o, $name) = @_;
    my $fm = $val->[0];
    my @F = sort grep { !$fm->is_system_field($_) } keys(%$fm);
    $o->{coverage} += scalar @F;
    my $big = @F > $o->{width};
    my $limit = $big ? $o->{summary_width}-1 : $#F;
    
    $o->o($name . " [");
    $o->nl;
    ++$o->{level};
    for my $x (0..$limit) {
	my $k = $F[$x];
	my $v = $val->[$fm->{$k}];
	
	$o->prefix;
	$o->o("$k => ");
	$o->{has_prefix}=1;
	$o->peek_any($v);
	$o->nl;
    }
    if ($big) { $o->prefix; $o->o("..."); $o->nl; }
    --$o->{level};
    $o->prefix;
    $o->o("],");
    $o->nl;
}

package ObjStore::Set;
use vars qw(@ISA);
@ISA=qw(ObjStore::HV);
use Carp;

sub new {
    require ObjStore::SetEmulation;
    ObjStore::SetEmulation::new(@_);
}

sub peek {
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
	$o->prefix;
	$o->peek_any($v);
	$o->nl;
    }
    if ($big) {
	$o->prefix;
	$o->o("...");
	$o->nl;
    }
    --$o->{level};
    $o->prefix;
    $o->o("],");
    $o->nl;
}

sub a { add(@_) }
sub r { rm($_[0], $_[1]) }
sub STORE { add(@_) }

package ObjStore;
$COMPILE_TIME = time;

package UNIVERSAL;

sub LEAVE_FOR {}

sub ABSORB {
    my ($class, $ref) = @_;
    CORE::bless($ref, $class);
}

1;
