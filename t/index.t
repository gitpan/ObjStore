#-*-perl-*-
BEGIN { $|=1; $tx=1; print "1..11\n"; }

use strict;
use ObjStore ':ADV';
use lib './t';
use test;
ObjStore::fatal_exceptions(0);

package Toy;
use base 'ObjStore::HV';

package Toy::AgeGrp;
use base 'ObjStore::AV';

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

    my $nx = ObjStore::Index->new($j);
    $nx->configure(path=>"name");
    
    my $ax = ObjStore::Index->new($j);
    $ax->configure(unique => 0, path=>"age/0, age/1");

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
	$nx->add($t);
	$ax->add($t);
    }

    # READONLY
    begin sub { $ages[0][0] = 0; };
    ok($@ =~ m'READONLY') or warn $@;

    $nx->[0]{'ok'} = 1;  #should allow writes

#    ok(readonly($nx->[0]{age}));  not yet
    begin sub { $nx->[0]{age}[3] = 3; };
    ok($@ =~ m'READONLY') or warn $@;

    # cursors
    my $c = $ax->new_cursor;
    ok($c->focus() == $ax) or warn $c->focus;
    ok(! $c->seek(2,5));
    $c->step(-1);
    ok(join('', $c->keys()) eq '24') or warn join('',$c->keys);
    my $at = $c->at;
    ok($at->{age}->[0] == 2);
    ok($at->{age}->[1] == 4);
    $c->moveto($c->pos);
    ok($c->at == $at);

    $ax->CLEAR();
    $nx->[0]{age}[3] = 3;

    $nx->map(sub { my $r = shift; ok(0) if $ax->add($r) != $r; });
    ok(1);

    begin sub {$nx->add(bless {name=>'Goldilocks'}, 'Toy'); };
    ok($@ =~ m'duplicate') or warn $@;
};
die if $@;
