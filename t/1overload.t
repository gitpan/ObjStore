#-*-perl-*-
use Test;
BEGIN { plan tests => 10 }

use ObjStore ':ADV';
use lib "./t";
use test;

my $undef = undef;

&open_db;
begin 'update', sub {
    my $john = $db->root('John');
    my $john_copy = $db->root('John');

    $john->{a} = [];
    $john->{h} = {};

    ok $john;
    ok !$john, '';
    ok $john == $undef, '';
    ok $john != $undef;
    ok $john == $john_copy;
    ok "$john" eq "$john_copy";

    my @fun = grep(ref, values %$john);
    ok(@fun > 2);
    my ($a,$b) = @fun;
    ok($a != $b);
    ok("$a" ne "$b");
};
