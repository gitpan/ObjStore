use strict;
package ObjStore::HV::Database; # document more XXX
use ObjStore;
use base 'ObjStore::Database';
use vars qw($VERSION);
$VERSION = '1.00';

sub ROOT() { 'hv' }  #DEPRECIATED XXX
sub hash { $_[0]->root(&ROOT, sub {new ObjStore::HV($_[0], 25)} ); }

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

sub POSH_ENTER { shift->hash; }

1;

=head1 NAME

    ObjStore::HV::Database - a generic hash-oriented database

=head1 SYNOPSIS

  package MyDatabase;
  use base 'ObjStore::HV::Database';

  my $db = MyDatabase->new("/path/to/my/database", 'update', 0666);

=head1 DESCRIPTION

Often you want to treat a database as a hash of related information.
Roots could be used, but there are a number of reasons to use this
class instead of roots:

=over 4

=item * PERFORMANCE

You have no control over the implementation of roots.  Performance is
unknown and cannot be changed.  

=item * FLEXIBILITY

If you want to move the top-level hash down to a deeper level, you
cannot easily do this with roots.

=item * NON-STANDARD

The standard way to create hash-oriented databases is with
C<ObjStore::HV::Database>.

=back

=head1 SEE ALSO

C<ObjStore>

=cut
