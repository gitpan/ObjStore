# Copyright (c) 1997 Joshua Nathaniel Pritikin.  All rights reserved.
# This package is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.
package ObjStore;
require 5.004;
use strict;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS $Exception);

$VERSION = 1.09;

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

sub PoweredByOS { "$Config{sitelib}/PoweredByOS.gif"; }

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

# Bless should be members of UNIVERSAL so it
# could be overridden in a reasonable way.

sub bless ($;$) {
    my ($ref, $class) = @_;
    $class = caller if !defined $class;
    if ($class->isa('ObjStore::UNIVERSAL') and
	ref($ref) and
	ref($ref) ne reftype($ref) and
	$ref->isa('ObjStore::UNIVERSAL')) {

	my $DB = ObjStore::Database::of($ref);
	my $root = $DB->_get_private_root;
	$root->{Brahma} = new ObjStore::HV($DB, 100) if !defined $root->{Brahma};
	my $bhava = $root->{Brahma};
	$bhava->{$class} = $class if !defined $bhava->{$class};
        ObjStore::UNIVERSAL::_bless($ref, $bhava->at($class));
    }
    CORE::bless $ref, $class;
}

sub peek {
    my $pk = new ObjStore::Peeker;
    $pk->Peek(@_);
}

package ObjStore::Peeker;
use strict;
use Carp;
use vars qw($LinePrefix $LineIndent $LineSep $SummaryWidth $MaxWidth $MaxDepth
	    $To $All);

$LinePrefix='';
$LineIndent='  ';
$LineSep="\n";
$SummaryWidth=3;
$MaxWidth=20;
$MaxDepth=20;
$To='string';
$All=0;

sub new {
    my ($class, %cnf) = @_;
    my $o = bless {
	prefix => $LinePrefix,
	indent => $LineIndent,
	sep => $LineSep,
	summary_width => $SummaryWidth,
	width => 20,
	depth => 20,
	level => 0,
	seen => {},
	to => $To,
	all => $All,
	output => '',
	has_sep => 0,
	has_prefix => 0,
	pct_unused => [],
    }, $class;
    while (my ($k,$v) = each %cnf) { $o->{$k} = $v; }
    $o;
}

sub Peek {
    my $o = shift;
    for my $top (@_) { $o->_peek($top); }
    $o->{output};
}

sub PercentUnused {
    my ($o) = @_;
    my $count=0;
    my $sum=0;
    for my $h (@{$o->{pct_unused}}) {
	$count += $h->{card};
	$sum += $h->{card} * $h->{unused};
    }
    $count = -1 if $count == 0;
    ($sum, $count);
}

sub prefix {
    my ($o) = @_;
    return if $o->{has_prefix};
    $o->o($o->{prefix}, $o->{indent} x $o->{level});
    $o->{has_prefix}=1;
}

sub nl {
    my ($o) = @_;
    return if $o->{has_sep};
    $o->o($o->{sep});
    $o->{has_sep}=1;
}

sub o {
    my $o = shift;
    $o->{has_sep}=0;
    $o->{has_prefix}=0;
    my $t = ref $o->{to};
    if (!$t and $o->{to} eq 'string') {
	$o->{output} .= join('', @_);
    } elsif ($t eq 'CODE') {
	$o->{to}->(@_);
    } elsif ($t->isa('IO::Handle') or $t->isa('FileHandle')) {
	$o->{to}->print(join('',@_));
    } else {
	die "ObjStore::Peeker: Don't know how to write to $o->{to}";
    }
}

sub _peek {
    my ($o, $val) = @_;
    my $type = ObjStore::reftype $val;
    my $class = ref $val;

    # Since persistent blessing might be turned off...
    $class = $val->_ref if ($class and $class->isa('ObjStore::UNIVERSAL'));

    if (!$class) {
	if (!defined $val) {
	    $o->o('undef,');
	} elsif ($val =~ /^-?[1-9]\d{0,8}$/) {
	    $o->o("$val,");
	} else {
	    $val =~ s/([\\\'])/\\$1/g;
	    $o->o("'$val',");
	}
	return;
    }

    # Stringification returns the transient address,
    # we want the persistent address!
    my $name;
    $name = $val->persistent_name if $val->can('persistent_name');
    $name = "$val" if !$name;

    if ($o->{level} > $o->{depth} or $o->{seen}{$name}) {
	if ($type eq 'HASH') {
	    $o->o("{ ... }");
	} elsif ($type eq 'ARRAY') {
	    $o->o("[ ... ]");
	} elsif ($class->isa('ObjStore::Set')) {
	    $o->o("[ ... ]");
	} else {
	    $o->o("$class ...");
	}
	return;
    }
    $o->{seen}{$name}=1;

    if ($val->can('cardinality') and $val->can('percent_unused')) {
	push(@{$o->{pct_unused}}, {card=>$val->cardinality,
				   unused=>$val->percent_unused});
    }

    $o->prefix;
    if ($class eq 'ObjStore::Database') {
	for my $r ($val->get_all_roots) {
	    next if (!$o->{all} and $r->get_name eq ObjStore::_PRIVATE_ROOT);

	    $o->prefix;
	    ++$o->{level};
	    $o->o("$r ",$r->get_name," = ");
	    $o->{has_prefix}=1;
	    $o->_peek($r->get_value);
	    --$o->{level};
	    $o->nl;
	}
    } elsif ($class->isa('ObjStore::Set')) {
	my @S;
	my $x=0;
	for (my $v=$val->first; $v; $v=$val->next) {
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
    } elsif ($type eq 'HASH') {
	my @S;
	my $x=0;
	while (my($k,$v) = each %$val) {
	    last if $x++ > $o->{width}+1;
	    push(@S, [$k,$v]);
	}
	@S = sort { $a->[0] cmp $b->[0] } @S;
	my $big = @S > 20;
	my $limit = $big ? $o->{summary_width}-1 : $#S;

	$o->o($name . " {");
	$o->nl;
	++$o->{level};
	for $x (0..$limit) {
	    my ($k,$v) = @{$S[$x]};

	    $o->prefix;
	    $o->o("$k => ");
	    $o->{has_prefix}=1;
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
	$o->o("},");
	$o->nl;
    } elsif ($type eq 'ARRAY') {
	croak "Peek doesn't do arrays yet";
    } else {
	die "Unknown type '$type'";
    }
}

package ObjStore::Database;
use Carp;

sub root {
    my ($o, $roottag, $nval) = @_;
    my $root = $o->find_root($roottag);
    $root = $o->create_root($roottag) unless $root;
    $root->set_value($nval) if $nval;
    $root->get_value();
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
