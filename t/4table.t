# tables and tables of -*-perl-*-
use Test;
BEGIN { plan tests => 4 }

use strict;
use ObjStore;
use lib './t';
use test;

&open_db;
begin 'update', sub {
    my $j = $db->root('John');
    die if !$j;

    require ObjStore::Table3;
    
    my $tbl = ObjStore::Table3->new($j);
    $tbl->add_index('id',
		   ObjStore::Index->new($j, path => 'id'));

    my @stuff = qw(alpha chicken chicken chicken rahim zapata);
    for (my $x=0; $x < @stuff; $x++) {
	my $o = ObjStore::HV->new($j, { name => $stuff[$x], id => $x });
	$tbl->add($o);
    }
    
    $tbl->add_index('name',
		   ObjStore::Index->new($j, path => 'name', unique => 0));

    $tbl->add(ObjStore::HV->new($j, { name => 'one leg', id => undef }));
    ok @{ $tbl->index('name') }, @{ $tbl->index('id') }+1;

    my @m = $tbl->fetch('name', 'chicken');
    ok join('', sort map { $_->{id} } @m), '123';

    ok $tbl->fetch('id', 3)->{id}, 3;
};
die if $@;
