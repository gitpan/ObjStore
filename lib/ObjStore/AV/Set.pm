use strict;

package ObjStore::AV::Set;
use base 'ObjStore::AV';
use vars qw($VERSION);
use Carp;
use ObjStore;

$VERSION = '0.03';

sub add {
    my ($o, $e) = @_;
    $o->PUSH($e);
    $e;
}

# depreciate? XXX
sub count {
    my ($o) = @_;
    my $c=0;
    my $sz = $o->FETCHSIZE();
    for (my $x=0; $x < $sz; $x++) {
	++$c if defined $o->[$x];
    }
    $c;
}

sub exists {
    my ($o,$e) = @_;
    defined $o->where($e);
}

sub where {
    my ($o, $e) = @_;
    my $x;
    for (my $z=0; $z < $o->FETCHSIZE(); $z++) {
	my $e2 = $o->[$z];
	do { $x = $z; last } if $e2 == $e;
    }
    $x;
}

sub remove {
    my ($o, $e) = @_;
    for (my $z=0; $z < $o->FETCHSIZE(); $z++) {
	while ($e == $o->[$z]) {
	    $o->SPLICE($z,1);
	}
    }
    $e;
}

sub map {
    my ($o, $sub) = @_;
    my @r;
    for (my $x=0; $x < $o->FETCHSIZE(); $x++) { 
	my $at = $o->[$x];
	next if !defined $at;
	push(@r, $sub->($at));
    }
    @r;
}

sub compress {
    carp "this is no longer necessary";
    # compress table - use with add/remove
    my ($ar) = @_;
    my $data = $ar->FETCHSIZE() - 1;
    my $hole = 0;
    while ($hole < $ar->FETCHSIZE()) {
	next if defined $ar->[$hole];
	while ($data > $hole) {
	    next unless defined $ar->[$data];
	    $ar->[$hole] = $ar->[$data];
	    $ar->[$data] = undef;
	} continue { --$data };
    } continue { ++$hole };
    
    while ($ar->FETCHSIZE() and !defined $ar->[$ar->FETCHSIZE() - 1]) {
	$ar->POP();
    }
}

1;
__END__;

=head1 NAME

  ObjStore::AV::Set - index-style interface with an array representation

=head1 SYNOPSIS

  my $set = ObjStore::AV::Set->new($near, $size);

  $set->add($myobject);

  $set->remove($myobject);

=head1 DESCRIPTION

Implements an API very similar to C<ObjStore::Index>, except with an
array implementation.  Elements are unsorted.  C<add> is O(1)
complexity while C<remove> always scans the entire set.  C<add> does
not check for duplicates, but C<remove> does.

This class may be useful as a primary index for C<ObjStore::Table3>.

=cut
