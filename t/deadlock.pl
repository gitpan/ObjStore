#-*-perl-*-

use ObjStore ':ALL';
set_transaction_priority(0);
set_max_retries(0);
use lib "./t";

CORE::open(STDOUT, ">>/dev/null") or die "open: $@";
CORE::open(STDERR, ">>/dev/null") or die "open: $@";

my $osdir = ObjStore->schema_dir;
my $db = ObjStore::open($osdir . "/perltest.db", 0, 0666);

try_update {
    my $left = $db->root('tripwire');
    ++ $left->{left};
    my $right = $db->root('John');
    $right->{right} = $left->{left};
};
