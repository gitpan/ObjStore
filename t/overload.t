#-*-perl-*-
BEGIN { $| = 1; $tx=1; print "1..4\n"; }

use ObjStore ':ALL';
use lib "./t";
use test;

&open_db;
try_read {
    my $john = $db->root('John');
    my $john_copy = $db->root('John');

    $john ? ok : not_ok;
    "$john" eq "$john_copy" ? ok : not_ok;

    my @fun = values %$john;
    @fun > 2 ? ok : not_ok;
    my ($a,$b) = @fun;
    "$a" eq "$b" ? not_ok : ok;
};
