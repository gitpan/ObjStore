# -*-perl-*- typemaps are confusing!
use Test;
BEGIN { plan test => 5, todo => [2] }

use strict;
use ObjStore;
use lib './t';
use test;

&open_db;
begin 'update', sub {
    my $h1 = ObjStore::HV->new($db);
    push @{$h1->{list}}, 'auto create';  #report to perlbug XXX
    ok ref $h1->{list}, '/AV/';
    ok @{$h1->{list}}, 1;

    my $h2 = ObjStore::HV->new($db);
    $$h1{hash} = {};
    $$h2{hash} = {};
    $$h1{hash}{hash} = {};
    $$h2{hash}{hash} = {};
    my $ih1 = $$h1{hash}{hash};
    my $ih2 = $$h2{hash}{hash};
    ok $ih1 != $ih2, 1;
#    ObjStore::debug qw(assign);
    # overload magic is not being used here! XXX
    ok $$h1{hash}{hash} != $$h2{hash}{hash}, 1, join(' != ', $ih1,$ih2);
};
