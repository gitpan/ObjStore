# This is obviously -*-perl-*- don'tcha-think?
BEGIN { $| = 1; $tx=1; print "1..21\n"; }

package Winner;

package main;

use strict;
use Carp;
use ObjStore ':ADV';
use lib './t';
use test;

#ObjStore::debug 'PANIC';

require PTest;
require TestDB;
$db = new TestDB(test_db(), 'update');
ref $db eq 'TestDB'? ok:not_ok;

# fold duplicated code XXX

sub _isa {
    no strict 'refs';
    my ($o, $c, $loop) = @_;
    my $err=0;
    $loop ||= 0;
    die "recursion $c" if $loop++ > 100;
    if (! $o->isa($c)) {
	warn "$o is not a $c\n";
	$err++;
    }
    for my $c (@{"$c\::ISA"}) { $err += _isa($o, $c, $loop); }
    $err;
}

sub isa_matches {
    no strict 'refs';
    my ($o) = @_;
    my $class = ref $o;
    my $err=0;
    for my $c (@{"$class\::ISA"}) { $err += _isa($o, $c); }
    !$err;
}

sub isa_test {
    no strict 'refs';
    my ($o) = @_;
    my $pkg = blessed($o);

    my $bs1 = $o->_blessto_slot;
    bless $o, blessed($o);
    my $bs2 = $o->_blessto_slot;
    $bs1 == $bs2 ?ok:not_ok;

    push(@{"$pkg\::ISA"}, 'Winner');
    $o->isa('Winner') ? not_ok:ok;
    $o->UNIVERSAL::isa('Winner') ? ok:not_ok;
    bless $o, $pkg;
    $bs2 = $o->_blessto_slot;
#    ObjStore::peek($bs2);
    $bs1 == $bs2 ? not_ok:ok;
    isa_matches($o)? ok:not_ok;

    pop @{"$pkg\::ISA"};
    $o->isa('Winner') ? ok:not_ok; #7
#    $o->UNIVERSAL::isa('Winner') ? not_ok:ok; #XXX
    bless $o, $pkg;
    isa_matches($o)? ok:not_ok;
}

begin 'update', sub {
    $db->get_INC->[0] = "./t";
    $db->sync_INC;

    isa_test($db);

    my $j = $db->root('John');
    die "john not found" if !$j;
    
    # basic bless
    my $phash = bless {}, 'Bogus';
    my $p1 = bless $phash, 'PTest';
    ref $p1 eq 'PTest' ? ok : do { not_ok; warn $p1; };
    
    $j->{obj} = $p1;
    ref $j->{obj} eq 'PTest' ? ok: do { not_ok; warn $j->{obj}; };

    $j->{obj} = new PTest($db);
    ref $j->{obj} eq 'PTest'? ok:not_ok;

    # object - changing @ISA
    my $o = $db->root('John')->{obj};
    isa_test($o);
};

begin sub {
    my $j = $db->root('John');
    my $o = $j->{obj};
    ref($o) eq 'PTest'? ok:not_ok;
    $o->bonk ? ok:not_ok;
};
