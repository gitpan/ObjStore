# This is -*-perl-*- !
use Test;
BEGIN { plan tests => 25, todo => [3,15] }

use strict;
use ObjStore;
use lib './t';
use test;

ObjStore::fatal_exceptions(0);

&open_db;
sub testify {
    no strict 'refs';
    my ($john, $rep) = @_;

    my $ok=1;
    
    my $new = $rep."::new";
    my $ah = &$new('ObjStore::HV', $db->segment_of, 5);
    die $ah if !$ah;
    ok($ah->os_class eq 'ObjStore::HV');
    ok($ah->rep_class eq $rep) or warn "$rep ne ".$ah->rep_class;

    begin sub { %$ah = (); };  #broken!
    ok(! $@);
    undef $@;

    ok(!defined $ah->FIRSTKEY());

    for (1..2) {
	$ah->CLEAR;
	for (1..8) {
	    my $tostore = ObjStore::translate($ah, { at => $_ });
	    my $stored = $ah->{$_} = $tostore;
	    $stored == $tostore or die "$stored != $tostore";
	    my @ks = keys %$ah;
	    $ah->count() == @ks or die "$rep $_ != ".$ah->count;
	    @ks == $_ or die "$rep $_ != ".@ks;
	}
    }

    $ah->{8} = "Replacement Test";
    ok($ah->{8} =~ /replace/i) or warn $ah->{8};

    ## strings work?
    my $pstr = pack('c4', 65, 66, 0, 67);
    $ah->{packed} = $pstr;
    ok($ah->{packed} eq $pstr) or do {
	print "ObjStore: " . join(" ", unpack("c*", $ah->{packed})) . "\n";
	print "perl:     " . join(" ", unpack("c*", $pstr)) . "\n";
    };
    delete $ah->{packed};

    ok(exists $ah->{1} && !exists $ah->{'not there'}) or warn "exists?";
    ok($ah->POSH_CD('1')->{at} == 1);

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

    $ah->const;
    begin sub { delete $ah->{1} };
    ok($@ =~ m/READONLY/) or warn $@;
    undef $@;

    delete $ah->{'not there'};

    @k = ();
    my $c = $ah->new_cursor;
    $c->moveto(-1);
    while (my ($k,$v) = $c->at) {
	push(@k, $k);
	$c->next;
    }
    ok(join('', sort @k) eq '1245678');
}

begin 'update', sub {
    my $john = $db->root('John');
    $john or die "no db";
    
    for my $rep (keys %ObjStore::HV::REP) {
	testify($john, $rep);
    }
};
die if $@;
