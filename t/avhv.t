# Give -*-perl-*- a kiss
BEGIN { $| = 1; $tx=1; print "1..5\n"; }

BEGIN { require 5.00452; }
use lib "./t";
use test;
use strict;
ObjStore::fatal_exceptions(0);

&open_db;

package Test::AVHV1;
use base 'ObjStore::AVHV';
use fields qw(my name is bob);  #must be AFTER 'use base'

package Test::AVHV2;
use base 'ObjStore::AVHV';
use fields qw(my pretty name is horsht);

package main;
use ObjStore;

#ObjStore::debug qw(wrap);

begin 'update', sub {
    my $john = $db->root('John');
    my $o = new Test::AVHV1($db);
    begin sub { $o->[0]{'my'} = 'bad'; };
    ok($@ =~ m'READONLY') or warn $@;
    undef $@;
    $john->{avhv} = $o;
    $o->{'my'} = 1;
    $o->{'name'} = 2;
    $o->{'is'} = 3;
    $o->{'bob'} = 4;
#    ObjStore::peek($o);
};
die if $@;

begin 'update', sub {
    my $john = $db->root('John');
    my $o = $john->{avhv};
    my $cnt = $o->count;
    bless $o, 'Test::AVHV2';
    ok(! $o->is_evolved);
    $o->evolve;
    ok($o->is_evolved, 3);
    ok($o->{'my'} == 1 and
       $o->{'name'} == 2 and
       $o->{'is'} == 3);
    $o->{horsht} = 5;
    $o->{pretty} = 4;

    # make sure traverse still works!
    my $x = new ObjStore::Index($o);
    $x->configure(path => 'name');
    $x->add($o);
#    warn "size $cnt ". $o->count();
#    ObjStore::peek($o->[0]);
};
die if $@;
