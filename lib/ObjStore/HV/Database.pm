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
