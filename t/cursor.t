# This is -*-perl-*- !
BEGIN { $| = 1; $tx=1; print "1..6\n"; }

use strict;
use ObjStore;
use lib './t';
use test;

&open_db;
sub chk1 {
    my ($john, $rep) = @_;

    my $ok=1;
    
    my $ah = $john->{$rep} = new ObjStore::HV($db, $rep, 7);
    die $ah if !$ah;
    for (1..8) {
      $ah->{$_} = 1;
      my @ks = keys %$ah;
      @ks == $_ or die "$rep cursor break at $_";
    }

    my @k = sort keys %$ah;
    @k == 8 or warn "$rep cursors are broken = @k";
    for (my $x=1; $x <= 8; $x++) {
	if ($k[$x-1] != $x) {
	    $ok=0;
	    warn "$k[$x-1] != $x";
	}
    }
    ok($ok);
    
    delete $ah->{3};
    @k = sort keys %$ah;
    for (my $x=0; $x < @k; $x++) {
	my $right = ($x >= 2? $x+2 : $x+1);
	if ($k[$x] != $right) {
	    $ok=0;
	    warn "$k[$x] != $right";
	}
    }
    ok($ok);
}

begin 'update', sub {
    my $john = $db->root('John');
    ok($john);
    
    for my $rep (keys %ObjStore::HV::REP) {
	chk1($john, $rep);
    }
};
