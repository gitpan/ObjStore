# This is -*-perl-*- !

use strict;
use vars qw($tx);
use ObjStore;

BEGIN { $| = 1; $tx=1; print "1..5\n"; }

sub ok { print "ok $tx\n"; $tx++; }
sub not_ok { print "not ok $tx\n"; $tx++; }

my $DB = ObjStore::Database->open(ObjStore->schema_dir . "/perltest.db", 0, 0666);

sub chk1 {
    my ($john, $rep) = @_;

    my $ok=1;
    
    my $ah = $john->{$rep} = new ObjStore::HV($DB, $rep);
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
    $ok? ok : not_ok;
    
    delete $ah->{3};
    @k = sort keys %$ah;
    for (my $x=0; $x < @k; $x++) {
	my $right = ($x >= 2? $x+2 : $x+1);
	if ($k[$x] != $right) {
	    $ok=0;
	    warn "$k[$x] != $right";
	}
    }
    $ok? ok : not_ok;
}

{
    try_update {
	my $john = $DB->root('John');
	$john ? ok : not_ok;

	chk1($john, 'array');
	chk1($john, 'dict');
    };
    print "[Abort] $@\n" if $@;
}
