# Copyright (c) 1997 Joshua Nathaniel Pritikin.  All rights reserved.
# This package is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.
package ObjStore;
require 5.004;
use strict;
use Carp;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS
	    $DEFAULT_OPEN_MODE $EXCEPTION %CLASSLOAD $CLASSLOAD);

$VERSION = '1.17';  #is a string, not a number!

require Exporter;
require DynaLoader;
@ISA         = qw(Exporter DynaLoader);
@EXPORT      = qw(&reval &bless &try_read &try_abort_only &try_update);
{
    my @x_adv = qw(&begin &translate &set_default_open_mode
		   &set_stargate &get_all_servers
		   &database_of &segment_of &get_lock_status
		   &is_lock_contention);
    my @x_tra = qw(&set_transaction_priority &peek &schema_dir
		   &reftype &rethrow_exceptions &release_name
		   &release_major &release_minor &release_maintenance
		   &network_servers_available 
		   &get_page_size &return_all_pages 
		   &get_max_retries &set_max_retries
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

bootstrap ObjStore $VERSION;

require ObjStore::GENERIC;

sub reftype ($);
sub bless ($;$);

sub schema_dir() {
    require ObjStore::Config;
    &ObjStore::Config::SCHEMA_DBDIR;
}

# code in XS?
sub begin {
    croak "begin(ttype, coderef)" if @_ != 2;
    my ($ttype, $code) = @_;
    if ($ttype eq 'read') { try_read(\&$code) }
    elsif ($ttype eq 'update') { try_update(\&$code) }
    elsif ($ttype eq 'abort_only') { try_abort_only(\&$code) }
    else { croak "Transaction type must be 'read', 'update', or 'abort_only'"; }
}

sub PoweredByOS {
    use Config;
    "$Config{sitelib}/ObjStore/PoweredByOS.gif";
}

# This can be expensive so it should only be called once per class.
#
# CLASSLOAD should not be a method of Database because it applies
# to all open databases.
$CLASSLOAD = sub {
    no strict 'refs';
    my ($db, $base, $class) = @_;
    
    my $file = $class;
    $file =~ s|::|/|g;
    $file .= ".pm";
#    ObjStore::reval(sub{ require $file });  XXX
    eval { require $file };
#    push(@LoadErrors, [$class, $@]) if $@;
    undef $@;
    push(@{"${class}::ISA"}, $base) if @{"${class}::ISA"} == 0;
    $class;
};

sub disable_auto_class_loading {
    $CLASSLOAD = sub {
	my ($db, $base, $class) = @_;
	$class;
    };
}
*ObjStore::disable_class_auto_loading = \&disable_auto_class_loading; #silly me

$EXCEPTION = sub {
    my $reason = shift;
    local($Carp::CarpLevel) = 1;
    confess "ObjectStore: $reason\t";
};

sub DEFAULT_STARGATE {
    my ($seg, $sv) = @_;
    my $type = reftype $sv;
    my $class = ref $sv;
    croak("$sv already persistent") if $class->isa('ObjStore::UNIVERSAL');
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

# switch to CORE::eval? XXX
sub reval($) {
    my $code = shift;
    my @r;
    if (ref $code) {
	@r = eval { &$code; };
    } else {
	@r = eval $code;
    }
    &ObjStore::_post_eval_cleanup();
    @r;
}

# Bless should be a member of UNIVERSAL, so I can override it
# with less impolite trickery.

sub bless ($;$) {
    my ($ref, $class) = @_;
    $class = caller if !defined $class;
    CORE::bless $ref, $class;  #? XXX
    &ObjStore::UNIVERSAL::_bless($ref, $class) if
	$ref->isa('ObjStore::UNIVERSAL');
    $ref;
}

sub lookup {
    my ($path, $mode) = @_;
    $mode = 0 if !defined $mode;
    _lookup($path, $mode);
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
    return if !$db;
    $db->open($mode);
}

sub peek {
    croak "ObjStore::peek(top)" if @_ != 1;
    require ObjStore::Peeker;
    my $pk = new ObjStore::Peeker;
    $pk->Peek($_[0]);
}

sub _debug {
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
	/^deadlock/ and $mask |= 1024, next;
	die "Smawgrev $_ tsanek bralwah";
    }
    __debug($mask);
}

package ObjStore::IgnoreBless::Not;  # This may disappear in the future.

sub new {
    my ($class) = @_;
    my $old = ObjStore::_to_bless(0);
    bless \$old, $class;
}

sub DESTROY {
    my ($old) = @_;
    ObjStore::_to_bless($$old);
}

package ObjStore::Database;
# Methods should not be overriden because databases are frequently
# derived from the memory address.

use Carp;

# simplify interface!
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
    $db;
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
    # delete until there is definitely data left.
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
    $o->_destroy if $empty;  #secret destroy method :-)
}

sub root {
    my ($o, $roottag, $nval) = @_;
    my $root = $o->find_root($roottag);
    if (defined $nval) {
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

sub _get_private_root {
    my ($DB) = @_;
    my $rt = $DB->_PRIVATE_ROOT();
    return undef if !$rt;
    my $priv = $rt->get_value;
    if (!$priv) {
	$priv = new ObjStore::HV($DB, 30);
	$rt->set_value($priv);
    }
    $priv;
}

sub _get_persistent_raw_string {
    my ($db, $class) = @_;
    $class .= "\x0";
    my $root = $db->_get_private_root;
    $root->{Brahma} = new ObjStore::HV($db, 30) if !$root->{Brahma};
    my $bhava = $root->{Brahma};
    $bhava->{$class} = $class if !$bhava->{$class};
    $bhava->_get_raw_string($class);
}

sub _peek {
    my ($val, $o) = @_;
    my $pr = $val->_PRIVATE_ROOT;
    my @priv = ($o->{all} and $pr)? $pr : ();
    for my $r ($val->get_all_roots, @priv) {
	$o->prefix;
	++$o->{level};
	my $name = $o->{addr}? "$r" : 'ObjStore::Root';
	$o->o("$name ",$r->get_name," = ");
	$o->{has_prefix}=1;
	$o->_peek($r->get_value);
	--$o->{level};
	$o->nl;
	++ $o->{coverage};
    }
}

sub newHV { carp 'depreciated'; new ObjStore::HV(@_); }
sub newTiedHV { carp 'depreciated'; new ObjStore::HV(@_); }
sub newSack { carp 'depreciated'; new ObjStore::Set(@_); }

package ObjStore::Database;
#use overload ('""' => \&get_id,
#	      'bool' => sub {1});

sub get_n_databases {
    carp "ObjStore::Database::get_n_databases depreciated; use ObjStore::get_n_databases";
    ObjStore::get_n_databases();
}

package ObjStore::Segment;
#use overload ('""' => \&get_number,
#	      'bool' => sub {1});

use Carp;
sub newHV { carp 'depreciated'; new ObjStore::HV(@_); }
sub newTiedHV { carp 'depreciated'; new ObjStore::HV(@_); }
sub newSack { carp 'depreciated'; new ObjStore::Set(@_); }

package ObjStore::UNIVERSAL;
use Carp;
use overload ('""' => \&_pstringify,
	      'bool' => sub {1});

sub persistent_name {
    carp 'persistent_name is depreciated, string operator is now overloaded';
    $_[0]->_pstringify;
}

#shallow copy
sub clone_to { croak($_[0]."->clone_to(where) unimplemented") }

package ObjStore::UNIVERSAL::Ref;
use vars qw(@ISA);
@ISA = qw(ObjStore::UNIVERSAL);

sub open {
    my ($r, $mode) = @_;
    my $db = $r->_get_database;  #can throw exception
    $db->open($mode) if !$db->is_open;
    die "Assertion failed: $r is broken" if $r->_broken;  #XXX
}

sub clone_to {
    my ($r, $seg, $cloner) = @_;
    $cloner->($r->focus)->new_ref($seg);
}

package ObjStore::UNIVERSAL::Cursor;
use vars qw(@ISA);
@ISA = qw(ObjStore::UNIVERSAL::Ref);

sub _peek {
    my ($val, $o, $name) = @_;
    ++ $o->{coverage};
    $o->o("$name => ");
    $o->{has_prefix}=1;
    ++ $o->{level};
    my $at = $val->focus;
    $o->_peek($at);
    -- $o->{level};
    $o->nl;
}

sub clone_to {
    my ($r, $seg, $cloner) = @_;
    $cloner->($r->focus)->new_cursor($seg);
}

package ObjStore::UNIVERSAL::Container;
use vars qw(@ISA);
@ISA = qw(ObjStore::UNIVERSAL);

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

package ObjStore::Set;
use vars qw(@ISA);
@ISA=qw(ObjStore::HV);
use Carp;

sub new {
    require ObjStore::SetEmulation;
    ObjStore::SetEmulation::new(@_);
}

sub _peek {
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
	$o->_peek($v);
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

1;
