# Copyright (c) 1997 Joshua Nathaniel Pritikin.  All rights reserved.
# This package is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.
package ObjStore;
require 5.004;
use strict;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS $Exception);

$VERSION = '1.10';  #is string, not a number!

use Carp;
use Config;

require Exporter;
require DynaLoader;
@ISA         = qw(Exporter DynaLoader);
@EXPORT      = qw(&bless &try_read &try_abort_only &try_update);
@EXPORT_OK   = qw(&peek &reftype &gateway &PoweredByOS 
		  &_PRIVATE_ROOT &DEFAULT_GATEWAY);
%EXPORT_TAGS = (ALL => [@EXPORT, @EXPORT_OK]);

bootstrap ObjStore $VERSION;

sub reftype ($);
sub bless ($;$);

sub PoweredByOS { "$Config{sitelib}/ObjStore/PoweredByOS.gif"; }

sub _PRIVATE_ROOT { "_osperl_private"; }

$Exception = sub {
    my $reason = shift;
    local($Carp::CarpLevel) = 1;
    confess "ObjectStore: $reason\t";
};

sub DEFAULT_GATEWAY {
    my ($seg, $sv) = @_;
    if (reftype $sv eq 'HASH') {
	my $hv = new ObjStore::HV($seg);
	while (my($hk,$v) = each %$sv) {
	    $hv->STORE($hk, $v);
	}
	my $class = ref $sv;
	if ($class ne 'HASH') { ObjStore::bless $hv, $class; }
	else { $hv; }
    } else {
	croak("ObjStore::DEFAULT_GATEWAY: Don't know how to translate $sv");
    }
};
gateway(\&DEFAULT_GATEWAY);

# Bless should be a member of UNIVERSAL so it
# could be overridden in a reasonable way.

sub bless ($;$) {
    my ($ref, $class) = @_;
    $class = caller if !defined $class;
    CORE::bless $ref, $class;

    if ($ref->isa('ObjStore::UNIVERSAL')) {
	my $DB = ObjStore::Database::of($ref);
	my $root = $DB->_get_private_root;
	$root->{Brahma} = new ObjStore::HV($DB, 'dict')
	    if !defined $root->{Brahma};
	my $bhava = $root->{Brahma};
	$bhava->{$class} = $class if !defined $bhava->{$class};
        ObjStore::UNIVERSAL::_bless($ref, $bhava->_at($class));
    }
    $ref;
}

sub peek {
    require ObjStore::Peeker;
    my $pk = new ObjStore::Peeker;
    $pk->Peek(@_);
}

package ObjStore::Database;
use Carp;

sub root {
    my ($o, $roottag, $nval) = @_;
    my $root = $o->find_root($roottag);
    if ($nval) {
	$root ||= $o->create_root($roottag);
	$root->set_value($nval) if $nval;
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
	$private = $DB->root(ObjStore::_PRIVATE_ROOT, new ObjStore::HV($DB, 100));
	$private->{VERSION} = 1.0;
    }
    $private;
}

sub newHV { carp 'depreciated'; new ObjStore::HV(@_); }
sub newTiedHV { carp 'depreciated'; new ObjStore::HV(@_); }
sub newSack { carp 'depreciated'; new ObjStore::Set(@_); }

package ObjStore::Segment;
use Carp;

sub newHV { carp 'depreciated'; new ObjStore::HV(@_); }
sub newTiedHV { carp 'depreciated'; new ObjStore::HV(@_); }
sub newSack { carp 'depreciated'; new ObjStore::Set(@_); }

package ObjStore::UNIVERSAL;
use Carp;
use overload (#'<=>' => \&_pcmp,
	      #'0+' => \&_paddress,
	      '""' => \&_pstringify,
	      'bool' => sub {1});

sub persistent_name {
    carp 'persistent_name is depreciated, string operator is now overloaded';
    $_[0]->_pstringify;
}

#XS: sub new($area, $rep, $card)

package ObjStore::HV;
use vars qw(@ISA $PICK_REP);
@ISA=qw(ObjStore::UNIVERSAL);

$PICK_REP = sub {
    my ($loc, $rep) = @_;
    my $seg = ObjStore::Segment::of($loc);
    if (!defined $rep) {
      ObjStore::UNIVERSAL::new($seg, 'ObjStore::HV::Array', 7);
    } elsif ($rep =~ /\d+/) {
	if ($rep < 20) {
	    ObjStore::UNIVERSAL::new($seg, 'ObjStore::HV::Array', $rep);
	} else {
	  ObjStore::UNIVERSAL::new($seg, 'ObjStore::HV::Dict', $rep);
	}
    } elsif ($rep eq 'array') {
	ObjStore::UNIVERSAL::new($seg, 'ObjStore::HV::Array', 10);
    } elsif ($rep eq 'dict') {
	ObjStore::UNIVERSAL::new($seg, 'ObjStore::HV::Dict', 107);
    } else {
	croak("ObjStore::HV::PICK_REP: rep '$rep' unknown");
    }
};

sub new {
    my ($class, $loc, $rep) = @_;
    my $o = $PICK_REP->($loc, $rep);
    ObjStore::bless($o, $class) if $class ne 'ObjStore::HV';
    $o;
}

package ObjStore::Set;
use vars qw(@ISA $PICK_REP);
@ISA=qw(ObjStore::UNIVERSAL);
use Carp;
#use overload ('+=' => \&a,
#	      '-=' => \&r);

$PICK_REP = sub {
    my ($loc, $rep) = @_;
    my $seg = ObjStore::Segment::of($loc);
    if (!defined $rep) {
      ObjStore::UNIVERSAL::new($seg, 'ObjStore::Set::Array', 7);
    } elsif ($rep =~ /\d+/) {
	if ($rep < 20) {
	  ObjStore::UNIVERSAL::new($seg, 'ObjStore::Set::Array', $rep);
	} else {
	  ObjStore::UNIVERSAL::new($seg, 'ObjStore::Set::Hash', $rep);
	}
    } elsif ($rep eq 'array') {
      ObjStore::UNIVERSAL::new($seg, 'ObjStore::Set::Array', 10);
    } elsif ($rep eq 'hash') {
      ObjStore::UNIVERSAL::new($seg, 'ObjStore::Set::Hash', 107);
    } else {
	croak("ObjStore::Set::PICK_REP: rep '$rep' unknown");
    }
};

sub new {
    my ($class, $loc, $rep) = @_;
    my $o = $PICK_REP->($loc, $rep);
    ObjStore::bless($o, $class) if $class ne 'ObjStore::Set';
    $o;
}

1;
