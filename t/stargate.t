#-*-perl-*-
BEGIN { $| = 1; $tx=1; print "1..5\n"; }

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
try_update {
    my $john = $db->root('John');
    $refs = $john->_refcnt;
    chk_refs($john->_refcnt, $refs); #1

    my $c = [$john, {1=>\$john}];
    $john->STORE('gated', $c);
    @$c == 0? ok:not_ok; #2

    chk_refs($john->_refcnt, $refs+2); #3
};

try_update {
    my $john = $db->root('John');
    chk_refs($john->_refcnt, $refs+2);
    $john->DELETE('gated');
    chk_refs($john->_refcnt, $refs);
};
