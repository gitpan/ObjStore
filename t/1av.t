#-*-perl-*-
use Test;
BEGIN { plan tests => 37, todo => [18] }

use ObjStore;
use lib './t';
use test;

ObjStore::fatal_exceptions(0);

#use Devel::Peek qw(Dump SvREFCNT);
#ObjStore::debug qw(refcnt bridge splash);

&open_db;
#    ObjStore::debug('PANIC');

sub testify {
    no strict 'refs';
    my ($j, $rep) = @_;

    print "# $rep\n";
    my $a = &{"$rep\::new"}('ObjStore::AV', $j->segment_of, 7);

    ok($a->os_class eq 'ObjStore::AV');
    ok($a->rep_class eq $rep) or warn "$rep ne ".$a->rep_class;

    ok(!defined $a->FETCH(-1));
    ok(!defined $a->POP());
    ok(!defined $a->SHIFT());

    for (1..2) {
	$a->CLEAR;
	ok($a->count == 0);
	for (0..50) {
	    $a->[$_] = [$_];
	}
	ok($a->count == 51) or warn $a->count;
    }
    ok($a->POSH_CD(2)->[0] == 2);

    ok($a->PUSH(69,[],1) == 3);
    ok($a->FETCH($a->FETCHSIZE()-1) == 1);
    for (1..2) { $a->POP; }
    my $e = $a->POP;
    ok($e, 69);
    
    ok($a->UNSHIFT(1,2,[]) == 3);
    ok($a->FETCH(0) == 1) or warn $a->FETCH(0);
    $a->SHIFT;
    $e = $a->SHIFT;
    ok($e, 2);
    $a->SHIFT;
    
    $a->const;

    begin sub { $a->[3] = 100 };
    ok($@ =~ m/READONLY/) or warn $@;

    my @k;
    my $c;
    begin sub { $c = $a->new_cursor; };
    undef $@;
    if ($c) {
	$c->moveto(-1);
	while (my ($k,$v) = $c->at) {
	    push(@k, $k);
	    $c->next;
	}
	ok(join('', sort @k) eq '01101112131415161718192202122232425262728293303132333435363738394404142434445464748495506789');
    } else {
	ok(0);
    }
};

require ObjStore::REP::Splash;
require ObjStore::REP::FatTree;

for my $rep (keys %ObjStore::AV::REP) {
    begin 'update', sub {
	my $john = $db->root('John');
	$john or die "no db";
	
	testify($john, $rep);
    };
    die if $@;
}
