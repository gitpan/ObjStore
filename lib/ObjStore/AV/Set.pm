use strict;

# Maybe store stats in the first slot?  Store version for now!

package ObjStore::AV::Set;
use base 'ObjStore::AV';
use vars qw($VERSION);
use Carp;
use ObjStore;

$VERSION = '0.01';

sub new {
    my $o = shift->SUPER::new(@_);
    $o->[0] = 1;
    $o;
}

sub add {
    my ($o, $e) = @_;
    $o->_Push($e);
    $e;
}

sub count {
    my ($o) = @_;
    my $c=0;
    for (my $x=1; $x < $o->SUPER::count(); $x++) {
	++$c if defined $o->[$x];
    }
    $c;
}

# Never returns zero!
sub exists {
    my ($o, $e) = @_;
    my $x;
    for (my $z=1; $z < $o->_count; $z++) {
	my $e2 = $o->[$z];
	do { $x = $z; last } if $e2 == $e;
    }
    $x;
}

sub remove {
    my ($ar, $e) = @_;
    my $x = $ar->exists($e);
    confess "$ar->remove($e): can't find element" if !defined $x;
    $ar->[ $x ] = undef;
    $e;
}

sub map {
    my ($o, $sub) = @_;
    my @r;
    for (my $x=1; $x < $o->_count; $x++) { 
	my $at = $o->[$x];
	next if !defined $at;
	push(@r, $sub->($at));
    }
    @r;
}

sub compress {
    # compress table - use with add/remove
    my ($ar) = @_;
    my $data = $ar->_count - 1;
    my $hole = 1;
    while ($hole < $ar->_count) {
	next if defined $ar->[$hole];
	while ($data > $hole) {
	    next unless defined $ar->[$data];
	    $ar->[$hole] = $ar->[$data];
	    $ar->[$data] = undef;
	} continue { --$data };
    } continue { ++$hole };
    
    while ($ar->_count and !defined $ar->[$ar->_count - 1]) {
	$ar->_Pop;
    }
}

1;
__END__;

=head1 NAME

  ObjStore::AV::Set - Simple set of objects using arrays

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 TODO

=over 4

=item * Documentation!

=back

=cut
