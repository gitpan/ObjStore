#-*-perl-*-
use Test 1.03;
BEGIN { plan tests=>2 }

use strict;
use ObjStore;
use lib './t';
use test;

#ObjStore::debug('refcnt');

&open_db;
begin 'update', sub {
    my $j = $db->root('John');

    my $h = $$j{heap} = ObjStore::REP::Splash::Heap::new('ObjStore::Index', $j->segment_of, 20);
    $h->configure(path => '0');
    my @db;
    for (reverse(1..25), 26..50) {
	my $e = $h->add([$_]);
	push @db, $e->HOLD;
    }
    my $s='';
    while (my $o = shift @$h) {
	$s .= $o->[0];
    }
    ok $s, join('', 1..50);

    for (reverse 1..5) { $h->add([$_]) }
};
