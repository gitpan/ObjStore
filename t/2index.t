# indexed -*-perl-*-
use Test 1.03;
BEGIN { plan tests=>29 }

use strict;
use ObjStore ':ADV';
use lib './t';
use test;
++$ObjStore::REGRESS;
ObjStore::fatal_exceptions(0);
#ObjStore::debug qw/ pathexam /;

# This should be rewritten with more complete checking and better
# factoring.

package Toy;
use base 'ObjStore::HV';
use vars qw($VERSION);
$VERSION = '0.0000';

package Toy::AgeGrp;
use base 'ObjStore::AV';
use vars qw($VERSION);
$VERSION = '0.0000';

package main;

my @TOYS = ('Bubble Mower',
	    'Discovery Beads',
	    'Pooh Memory Game',
	    'Hugg America',
	    'Solar System Mobile',
	    'Glow Stickables',
	    'Storytime Finger Puppets',
	    'Goldilocks',
	    'Tickle Me Cookie Monster',
	    'Beanie Babies',
	    'Barbie as Sleeping Beauty',
	   );

&open_db;
begin 'update', sub {
    my $j = $db->root('John');
    die 'john' if !$j;

    do { # numeric comparisons
	my $nums = ObjStore::Index->new($j, path => 'num', unique => 0);
	for (1..5) {
	    $nums->add({num => $_});
	    $nums->add({num => .5 * $_});
	    $nums->add({num => -80000 + $_ * 40000 });
	    $nums->add({typo => 20 * $_});
	}
	my $e = ObjStore::HV->new($nums, { typo => 20 });
#	$nums->remove($e);
#	for (.0005, .5, $nums->[$nums->FETCHSIZE()-1]->{num}) {
#	    $e->{num} = $_;
#	    $nums->remove($e);
#	}
	my $n = $nums->[0];
	begin sub { $n->{num} *= 2 };
	ok $@, '/READONLY/';
	ok(($n->{'notnum'}=1), 1);
	begin sub { $n->{num} = 0; };
	ok $@, '/READONLY/';

	my @nums;
	$nums->map(sub { push(@nums, shift->{num}) });
	
	my @sorted = sort { $a <=> $b } @nums;
	my $ok=1;
	for (my $x=0; $x < @nums; $x++) { $ok=0, last if $nums[$x] != $sorted[$x] }
	ok($ok);

	my $c = $nums->new_cursor;
	begin sub { $c->each('bogus'); };
	ok $@, '/integer/';

	my $total=0;
	while (my $n = $c->each(1)) { $total+= $n->{num}; }
	ok $total, 200022.5;

	begin sub { $c->store([]); };
	ok $@, '/unavailable/';

	ok !$nums->add($nums->[0]), 1;
	begin sub { $n->{num} = 0; };
	ok $@, '/READONLY/';

	my $numsdup = ObjStore::Index->new($j, path => 'num', unique => 0);
	$ok = begin sub { $numsdup->add($nums->[0]); 1; };
	ok $@, '/multiple/';

	$n->HOLD;
	$nums->CLEAR();
	ok($n->{num} = 42,42);
    };

    #---------------------

    my $nx = ObjStore::Index->new($j);
    $nx->configure(path=>"name");
    $nx->configure(path=>"name");
    
    my $ax = ObjStore::Index->new($j);
    ok(!defined $ax->[0]);
    $ax->configure(unique => 0, path=>"age/0");

    my @ages;
    push(@ages, 
	 new Toy::AgeGrp($j, [1,3]),
	 new Toy::AgeGrp($j, [2,4]),
	 new Toy::AgeGrp($j, [2,7]),
	 new Toy::AgeGrp($j, [6,12]),
	 new Toy::AgeGrp($j, [5,32]),
	);

    srand(0);
    for my $n (@TOYS) {
	my $t = new Toy($j, { 
			     name => $n,
			     age => $ages[int(rand(@ages))],
			    });
	$t->{age}->const;
	$nx->add($t);
	$ax->add($t);
    }
    ok $nx->count, 11;

    $nx->map(sub { my $t=shift; $ax->add($t) });  #test non-unique add

    $ax->map(sub { my $t=shift; $nx->add($t) });  #test unique add

    # READONLY
    begin sub { $ages[0][0] = 0; };
    ok $@, '/READONLY/';
    $@=undef;

    $nx->[0]{age}[3] = 3;
    $nx->[0]{'ok'} = 1;  #should allow writes
    $nx->add($nx->[0]);  #re-add is ok

#    ok(readonly($nx->[0]{age}));  not yet

    eval { $nx->[0]{age}[0] = 3; };
    ok $@, '/READONLY/';

    # cursors
    my $c = $ax->new_cursor;
#    ok(! $c->deleted);
#    ok($c->get_database->get_id eq $db->get_id);
    ok($c->focus() == $ax) or warn $c->focus;
#    ObjStore::debug qw(assign);
    ok $c->seek($ax->[0]{age}[0], $ax->[0]{age}[1]);
    ok(! $c->seek());
    ok(! $c->seek(4));
    $c->step(-1);
    ok join('', $c->keys()), '2';
    my $at = $c->at;
    ok $at->{age}->[0], 2;
    ok $at->{age}->[1], 4;
    $c->moveto($c->pos);
    ok($c->at == $at);

    # readonly flags again
    my $decoy = $ax->add(new Toy($j, {name => 'Decoy',
				      age => bless [1,3], 'Toy::AgeGrp'}));
    ok $decoy->{name}, 'Decoy';
    $ax->remove($ax->[1]); #will seek to [0] first
    $ax->CLEAR();
    ok(!defined $ax->[0]);

    begin sub { $nx->[0]{age}[0] = 3; };
    ok $@, '/READONLY/';

    $nx->map(sub { my $r = shift; ok(0) if $ax->add($r) != $r; });
    ok(1);

    begin sub {$nx->add(bless {name=>'Goldilocks'}, 'Toy'); };
    ok $@, '/Goldilocks/';

    $nx->remove($nx->[0]); #hit coverage case
};
die if $@;