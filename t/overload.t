#-*-perl-*-
BEGIN { $| = 1; $tx=1; print "1..9\n"; }

use ObjStore ':ADV';
use lib "./t";
use test;

&open_db;
begin sub {
    my $john = $db->root('John');
    my $john_copy = $db->root('John');

    ok($john);
    ok(! ($john == 'john'));
    ok($john != 'john');
    ok($john == $john_copy);
    ok("$john" eq "$john_copy");

    my @fun = grep(ref, values %$john);
    ok(@fun > 2);
    my ($a,$b) = @fun;
    ok($a != $b);
    ok("$a" ne "$b");
};
