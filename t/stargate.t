#-*-perl-*-
BEGIN { $| = 1; $tx=1; print "1..6\n"; }

use Carp;
use ObjStore;
use lib './t';
use test;

sub chk_refs {
    my ($r1, $r2) = @_;
    ok($r1 == $r2) or carp "[$tx] refs wrong by ".($r1-$r2);
}

my $refs;

&open_db;
begin 'update', sub {
    my $john = $db->root('John');
    $refs = $john->_refcnt;
    chk_refs($john->_refcnt, $refs); #1

    my $c = [$john, {1=>\$john}];
    $john->STORE('gated', $c);
    ok(@$c != 0);

    chk_refs($john->_refcnt, $refs+1); #3
};

begin 'update', sub {
    my $john = $db->root('John');
    chk_refs($john->_refcnt, $refs+1);
    $john->DELETE('gated');
    chk_refs($john->_refcnt, $refs);
};
