use strict;
package ObjStore::REP;
use Carp;
use ObjStore;

sub be_compatible {
    # I'm not sure how to make this more conditional? XXX
    require ObjStore::REP::Splash;
    require ObjStore::REP::FatTree;
    require ObjStore::REP::ODI;
}

sub load_default {
    my $ty = caller;
    my $sub;
    if ($ty eq 'ObjStore::AV') {
	require ObjStore::REP::Splash;
	require ObjStore::REP::FatTree;
	$sub = \&AV;
    } elsif ($ty eq 'ObjStore::HV') {
	require ObjStore::REP::Splash;
	require ObjStore::REP::ODI;
	$sub = \&HV;
    } elsif ($ty eq 'ObjStore::Index') {
	require ObjStore::REP::FatTree;
	$sub = \&Index;
    } else {
	croak "load_default($ty)?";
    }
    {
	no strict 'refs';
	local $^W = 0;
	*{"$ty\::new"} = $sub;
    }
    goto &$sub;
}

sub AV {
    my ($this, $loc, $how) = @_;
    $loc = $loc->segment_of if ref $loc;
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

sub HV {
    my ($this, $loc, $how) = @_;
    $loc = $loc->segment_of if ref $loc;
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

sub Index {
    my ($this, $loc, @CONF) = @_;
    $loc = $loc->segment_of if ref $loc;
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

1;

=head1 NAME

    ObjStore::REP - Setup Default Data Representations

=head1 SYNOPSIS

    *ObjStore::AV::new = sub { ... };

=head1 DESCRIPTION

The most suitable representation for data-types is determined when
they are allocated.  The code that does the determination is set up by
this file.

To override the defaults, simply re-implement the 'new' method for the
classes of your choice before you allocate anything.

=cut

