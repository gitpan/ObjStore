#-*-perl-*-
use Test;
BEGIN { todo test => 6 }

use Carp;
use ObjStore;
use lib './t';
use test;

sub chk_refs {
    my ($r1, $r2) = @_;
    ok($r1 == $r2) or carp "[$ntest] refs wrong by ".($r1-$r2);
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
