#-*-perl-*-
use Test;
BEGIN { todo tests => 10 }

use ObjStore;
use lib './t';
use test;

ObjStore::fatal_exceptions(0);

#use Devel::Peek qw(Dump SvREFCNT);
#ObjStore::debug qw(PANIC);

&open_db;

sub testify {
    no strict 'refs';
    my ($j, $rep) = @_;

    my $a = &{"$rep\::new"}('ObjStore::AV', $j->segment_of, 7);
    ok($a->os_class eq 'ObjStore::AV');
    ok($a->rep_class eq $rep) or warn "$rep ne ".$a->rep_class;

    for (1..2) {
	$a->CLEAR;
	for (-1..20) {
	    $a->[$_] = [$_];
	}
	ok($a->count == 21);
    }
    ok($a->POSH_CD(2)->[0] == 2);
    ok(!defined $a->[-2]);

    $a->_Push(69);
    my $e = $a->_Pop;
    ok($e == 69) or warn $e;
    
    $a->const;

    begin sub { $a->[3] = 100 };
    ok($@ =~ m/READONLY/) or warn $@;
    undef $@;

    my @k;
    my $c = $a->new_cursor;
    $c->moveto(-1);
    while (my ($k,$v) = $c->at) {
	push(@k, $k);
	$c->next;
    }
    ok(join('', sort @k) eq '01101112131415161718192203456789');
};

begin 'update', sub {
    my $john = $db->root('John');
    $john or die "no db";
    
    for my $rep (keys %ObjStore::AV::REP) {
	testify($john, $rep);
    }
};
die if $@;
