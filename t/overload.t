#-*-perl-*-
BEGIN { $| = 1; $tx=1; print "1..9\n"; }

use ObjStore ':ADV';
use lib "./t";
use test;

&open_db;
begin sub {
    my $john = $db->root('John');
    my $john_copy = $db->root('John');

    $john ? ok : not_ok;
    $john == 'john'? not_ok:ok;
    $john != 'john'? ok:not_ok;
    $john == $john_copy ? ok : not_ok;
    "$john" eq "$john_copy" ? ok : not_ok;

    my @fun = grep(ref, values %$john);
    @fun > 2 ? ok : not_ok;
    my ($a,$b) = @fun;
    $a != $b ? ok : not_ok;
    "$a" eq "$b" ? not_ok : ok;
};
