# Copyright (c) 1997 Joshua Nathaniel Pritikin.  All rights reserved.
# This package is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.
package ObjStore;
require 5.004;
use strict;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS
	    $EXCEPTION %CLASSLOAD $CLASSLOAD);

$VERSION = '1.15';  #is a string, not a number!

use Carp;
use Config;

require Exporter;
require DynaLoader;
@ISA         = qw(Exporter DynaLoader);
@EXPORT      = qw(&bless &try_read &try_abort_only &try_update);
{
    my @x_tra = qw(&peek &reftype &schema_dir &set_gateway 
		   &release_name &release_major &release_minor &release_maintenance
		   &network_servers_available 
		   &get_page_size &return_all_pages &get_lock_status
		   &set_transaction_priority &is_lock_contention
		   &get_max_retries &set_max_retries
		   &get_readlock_timeout &get_writelock_timeout
		   &set_readlock_timeout &set_writelock_timeout
		   &abort_in_progress
		   &get_all_servers &get_n_databases
		   &set_auto_open_mode &database_of &segment_of
		   &DEFAULT_GATEWAY &PoweredByOS);

    %EXPORT_TAGS = (ALL => [@EXPORT, @x_tra]);

    my @x_old = qw(&gateway);
    my @x_priv = qw(%CLASSLOAD $CLASSLOAD $EXCEPTION &_PRIVATE_ROOT);

    @EXPORT_OK   = (@EXPORT, @x_tra, @x_old, @x_priv);
}

bootstrap ObjStore $VERSION;

sub reftype ($);
sub bless ($;$);

sub _PRIVATE_ROOT { "_osperl_private"; }

sub PoweredByOS { "$Config{sitelib}/ObjStore/PoweredByOS.gif"; }

# This can be expensive since it should only be called once per class.
#
# CLASSLOAD should not be a method of Database because it applies
# to all open databases.
$CLASSLOAD = sub {
    my ($db, $class) = @_;

    # load it
    $CLASSLOAD{$class} = 1;
    $class =~ s|::|/|g;
    $class .= ".pm";
    require $class;
};

sub disable_auto_class_loading {
    $CLASSLOAD = sub {
	my ($db, $class) = @_;
	$CLASSLOAD{$class} = 1;
    };
}

$EXCEPTION = sub {
    my $reason = shift;
    local($Carp::CarpLevel) = 1;
    confess "ObjectStore: $reason\t";
};

sub DEFAULT_GATEWAY {
    my ($seg, $sv) = @_;
    my $type = reftype $sv;
    my $class = ref $sv;
    if ($type eq 'HASH') {
	my $hv = new ObjStore::HV($seg);
	while (my($hk,$v) = each %$sv) { $hv->STORE($hk, $v); }
	if ($class ne 'HASH') { ObjStore::bless $hv, $class; }
	else { $hv }
    } elsif ($type eq 'ARRAY') {
	my $av = new ObjStore::AV($seg, scalar(@$sv));
	for (my $x=0; $x < @$sv; $x++) { $av->STORE($x, $sv->[$x]); }
	if ($class ne 'ARRAY') { ObjStore::bless $av, $class; }
	else { $av }
    } else {
	croak("ObjStore::DEFAULT_GATEWAY: Don't know how to translate $sv");
    }
};
set_gateway(\&DEFAULT_GATEWAY);
sub gateway { carp 'depreciated; call set_gateway instead'; set_gateway(@_); }

# Bless should be a member of UNIVERSAL so we can override it
# in a less impolite manner.

sub bless ($;$) {
    my ($ref, $class) = @_;
    $class = caller if !defined $class;
    CORE::bless $ref, $class;
    &ObjStore::UNIVERSAL::_bless($ref, $class) if
	$ref->isa('ObjStore::UNIVERSAL');
    $ref;
}

sub peek {
    require ObjStore::Peeker;
    my $pk = new ObjStore::Peeker;
    $pk->Peek(@_);
}

package ObjStore::Database;
# Methods should not be overriden because databases are frequently
# derived from the memory address.

use Carp;

sub root {
    my ($o, $roottag, $nval) = @_;
    my $root = $o->find_root($roottag);
    if (defined $nval) {
	$root ||= $o->create_root($roottag);
	$root->set_value($nval);
    }
    $root? $root->get_value() : undef;
}

sub destroy_root {
    my ($o, $tag) = @_;
    my $root = $o->find_root($tag);
    $root->destroy if $root
}

sub _get_private_root {
    my ($DB) = @_;
    my $private = $DB->root(ObjStore::_PRIVATE_ROOT);
    if (!$private) {
	my $tr = ObjStore::Transaction::get_current();
	if ($tr and $tr->get_type() ne 'read') {
	    $private = $DB->root(ObjStore::_PRIVATE_ROOT,
				 new ObjStore::HV($DB, 100));
	    $private->{VERSION} = 1.0;
	}
    }
    $private;
}

sub _get_persistent_raw_string {
    my ($db, $class) = @_;
    my $root = $db->_get_private_root;
    $root->{Brahma} = new ObjStore::HV($db, 30) if !$root->{Brahma};
    my $bhava = $root->{Brahma};
    $bhava->{$class} = $class if !$bhava->{$class};
    $bhava->_at($class);
}

sub newHV { carp 'depreciated'; new ObjStore::HV(@_); }
sub newTiedHV { carp 'depreciated'; new ObjStore::HV(@_); }
sub newSack { carp 'depreciated'; new ObjStore::Set(@_); }

package ObjStore::Database;

use Carp;
sub open {
    croak "ObjStore::Database->open(...) depreciated; use ObjStore::open" if @_ != 4;
    carp "ObjStore::Database->open(...) depreciated; use ObjStore::open";
    shift;
    ObjStore::open(@_);
}

sub get_n_databases {
    carp "ObjStore::Database::get_n_databases depreciated; use ObjStore::get_n_databases";
    ObjStore::get_n_databases();
}

package ObjStore::Segment;
# Methods should not be overriden because segments are frequently
# derived from the memory address.

use Carp;
sub newHV { carp 'depreciated'; new ObjStore::HV(@_); }
sub newTiedHV { carp 'depreciated'; new ObjStore::HV(@_); }
sub newSack { carp 'depreciated'; new ObjStore::Set(@_); }

package ObjStore::Transaction;
use Carp;

package ObjStore::UNIVERSAL;
use Carp;
use overload ('""' => \&_pstringify,
	      'bool' => sub {1});

sub persistent_name {
    carp 'persistent_name is depreciated, string operator is now overloaded';
    $_[0]->_pstringify;
}

#XS: sub new($area, $rep, $card)

require ObjStore::GENERIC;

1;
