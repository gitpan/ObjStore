#-*-perl-*-
BEGIN { $| = 1; $tx=1; print "1..6\n"; }

use Carp;
use ObjStore;
use lib './t';
use test;

sub chk_refs {
    my ($r1, $r2) = @_;
    if ($r1 == $r2) {ok} else {
	carp "[$tx] refs wrong by ".($r1-$r2);
	not_ok;
    }
}

my $refs;

&open_db;
begin 'update', sub {
    my $john = $db->root('John');
    $refs = $john->_refcnt;
    chk_refs($john->_refcnt, $refs); #1

    my $c = [$john, {1=>\$john}];
    $john->STORE('gated', $c);
    @$c == 0? not_ok:ok; #2

    chk_refs($john->_refcnt, $refs+1); #3
};

begin 'update', sub {
    my $john = $db->root('John');
    chk_refs($john->_refcnt, $refs+1);
    $john->DELETE('gated');
    chk_refs($john->_refcnt, $refs);
};
