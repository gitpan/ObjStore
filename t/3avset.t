# set -*-perl-*-
use Test;
BEGIN { todo tests => 5; }

use strict;
use ObjStore ':ADV';
require ObjStore::AV::Set;
use lib './t';
use test;

&open_db;
begin 'update', sub {
    my $j = $db->root('John');
    die "no db" if !$j;

    my $s = new ObjStore::AV::Set($j, 12);

    $s->add({box => 1});
    $s->add({box => 2});
    $s->add({box => 2});

    my @b;
    $s->map(sub { push(@b, shift) });
    ok(@b == 3);

    ok($s->exists($b[0]));
    $s->remove($b[1]);
#    peek $s;

    @b=();
    $s->compress;
    $s->map(sub { push(@b, shift) });
    ok(@b == 2) or warn @b;

    ok($s->count == 2) or warn $s->count;
};