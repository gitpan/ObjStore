# -*-perl-*- is going global, I tell ya!
BEGIN { $| = 1; $tx=1; print "1..3\n"; }

package MyGSpot;
use ObjStore;
use base 'ObjStore::AV';
use vars qw($VERSION);
$VERSION = "0.5";

package main;

use strict;
use ObjStore ':ADV';
use lib './t';
use test;

&open_db;
begin 'update', sub {
    my $j = $db->root('John');
    die "no db" if !$j;

    my $s = new MyGSpot($j);
    my $g = $s->GLOBS;
    $g->{color} = 'Pink';
    $g->{size} = 10;
};

begin sub {
    my $g = $db->GLOBS('MyGSpot');
    ok($g->{color} eq 'Pink');
    ok($g->{size} == 10);
};
