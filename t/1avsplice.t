#-*-perl-*-
use Test;
BEGIN { plan tests => 29 }

use ObjStore;
use lib './t';
use test;

ObjStore::fatal_exceptions(0);
&open_db;

sub tostr($) {
    my $a = shift;
    my $s='';
    for (my $x=0; $x < $a->FETCHSIZE; $x++) {
	$s .= $a->[$x];
    }
    $s;
}

sub testify {
    no strict 'refs';
    my ($j, $rep) = @_;

    print "# $rep\n";
    my $a = &{"$rep\::new"}('ObjStore::AV', $j->segment_of, 7);

    $a->SPLICE(0, 0, 1,2,3);
    ok(tostr($a) == '123');
    
    my $shift = $a->SPLICE(0, 1);
    ok($shift == 1) or warn $shift;
    ok(tostr($a) eq '23');

    my $pop = $a->SPLICE(-1);
    ok($pop == 3) or warn $pop;
    ok(tostr($a) eq '2') or warn tostr($a);

    $a->SPLICE($a->FETCHSIZE, 0, 3,4,5);
    ok(tostr($a) eq '2345') or warn tostr($a);
    
    $a->SPLICE(0, 0, 0,1);
    ok(tostr($a) eq '012345') or warn tostr($a);

    $a->SPLICE(0, 4, 2,1,0);
    ok(tostr($a) eq '21045') or warn tostr($a);

    my @d = $a->SPLICE(0);
    ok($a->FETCHSIZE == 0);
    ok(join('',@d) eq '21045') or warn @d;

    $a->SPLICE(0,0, [],{},[]);
    ok(ref $a->[0] eq 'ObjStore::AV') or warn ref $a->[0];
    ok(ref $a->[1] eq 'ObjStore::HV') or warn ref $a->[1];
    ok(ref $a->[2] eq 'ObjStore::AV') or warn ref $a->[2];

    $a->SPLICE(20,-1, 1,2);
    ok($a->FETCH(4) == 2);
}

begin 'update', sub {
    my $john = $db->root('John');
    $john or die "no db";
    
    for my $rep (keys %ObjStore::AV::REP) {
	testify($john, $rep);
    }
};
die if $@;
