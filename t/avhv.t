# Give -*-perl-*- a kiss
BEGIN { $| = 1; $tx=1; print "1..3\n"; }

BEGIN { require 5.00452; }
use lib "./t";
use test;
use strict;

&open_db;

package Test::AVHV1;
use base 'ObjStore::AVHV';
use Class::Fields qw(my name is bob);  #must be AFTER 'use base'

package Test::AVHV2;
use base 'ObjStore::AVHV';
use Class::Fields qw(my pretty name is horsht);

package main;
use ObjStore;

#ObjStore::debug qw(wrap);

begin 'update', sub {
    my $john = $db->root('John');
    my $o = new Test::AVHV1($db);
    $john->{avhv} = $o;
    $o->{'my'} = 1;
    $o->{'name'} = 2;
    $o->{'is'} = 3;
    $o->{'bob'} = 4;
#    warn ObjStore::peek($o);
};

begin 'update', sub {
    my $john = $db->root('John');
    my $o = $john->{avhv};
    bless $o, 'Test::AVHV2';
    $o->is_evolved ? not_ok : ok;
    $o->evolve;
    ($o->{'my'} == 1 and
     $o->{'name'} == 2 and
     $o->{'is'} == 3) ? ok : not_ok;
    $o->{horsht} = 5;
    $o->{pretty} = 4;
#    ObjStore::peek($o);
};
