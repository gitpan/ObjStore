# Give -*-perl-*- a kiss

BEGIN {
    $| = 1; 
    print("1..0\n"), exit if $]<5.00452;
    $tx=1; print "1..4\n";
}

use lib "./t";
use test;
use strict;
ObjStore::fatal_exceptions(0);

&open_db;

package Test::AVHV1;
use base 'ObjStore::AVHV';
use fields qw(my name is bob);  #must be AFTER 'use base'
use vars qw($VERSION);
$VERSION = '0.00';

package Test::AVHV2;
use base 'ObjStore::AVHV';
use fields qw(my pretty name is horsht);
use vars qw($VERSION);
$VERSION = '0.00';

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
    ok($o->is_evolved);
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

    # don't mess up z_peek.t by leaving 5.004_50 stuff in the database
    delete $john->{avhv};
};
die if $@;
