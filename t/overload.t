#-*-perl-*-

BEGIN { $| = 1; $tx=1; print "1..4\n"; }
sub ok { print "ok $tx\n"; $tx++; }
sub not_ok { print "not ok $tx\n"; $tx++; }
use ObjStore ':ALL';
use lib "./t";

my $osdir = ObjStore->schema_dir;
my $DB = ObjStore::open($osdir . "/perltest.db", 0, 0666);

try_read {
    my $john = $DB->root('John');
    my $john_copy = $DB->root('John');

    $john ? ok : not_ok;
    "$john" eq "$john_copy" ? ok : not_ok;

    my @fun = values %$john;
    @fun > 2 ? ok : not_ok;
    my ($a,$b) = @fun;
    "$a" eq "$b" ? not_ok : ok;
};
die if $@;
