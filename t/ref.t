# Test broken -*-perl-*- refs
BEGIN { $| = 1; $tx=1; print "1..13\n"; }

use strict;
use ObjStore;
use lib './t';
use test;

package noref_test;
use test;
use vars qw(@ISA);
@ISA = 'ObjStore::AV';

sub NOREFS {
    my $o = shift;
    ok;  # should be called exactly twice
    if ($main::saver->[0]) {
	$main::saver->[1] = $o;
    }
}

package main;
use vars qw($saver);

ObjStore::fatal_exceptions(0);
#ObjStore::debug qw( bridge);
#use Devel::Peek;

&open_db;

my $t;
my ($safe, $unsafe);

begin('update', sub {
    my $j = $db->root('John');

    my $toast = [ObjStore::translate($j, [1,2]), ObjStore::translate($j, [1,2])];
    $j->{'toast'} = $toast->[1];

    for (my $x=0; $x < @$toast; $x++) {
	for my $type ('safe', 'unsafe') {
	     my $r = $toast->[$x]->new_ref('transient', $type);
	     $r->deleted? not_ok:ok;
	     $t->[$x]{$type} = $r;
	}
    }
    $safe = $t->[1]{safe}->dump;
    $unsafe = $t->[1]{unsafe}->dump;

    #norefs
    $saver = new ObjStore::AV($db);
    $saver->[0] = 1;
    new noref_test($db);
    undef $saver;
});
die if $@;

begin sub {
    my $j = $db->root('John');

    # $t->[0] should be deleted now
    $t->[0]{safe}->deleted ? ok:not_ok;
    begin sub { $t->[0]{safe}->focus };
    $@ =~ m/err_reference_not_found/s? ok:not_ok;

    $t->[1]{safe}->deleted ? not_ok:ok;

    my $toast = $j->{'toast'};

    for my $o (ObjStore::Ref->load($safe, $db)->focus,
	     ObjStore::Ref->load($unsafe, $db)->focus) {
	"$o" eq "$toast"? ok:not_ok;
    }
};
die if $@;

begin('update', sub {
    my $j = $db->root('John');
    delete $j->{'toast'};
});
$@? not_ok:ok;

# Also should test broken cross-database ref XXX
