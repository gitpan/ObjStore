#-*-perl-*-

use ObjStore ':ALL';
set_transaction_priority(0);
set_max_retries(0);
use lib "./t";
use test;

#open(STDOUT, ">>/dev/null") or die "open: $@";
#open(STDERR, ">>/dev/null") or die "open: $@";

&open_db;
try_update {
    my $left = $db->root('tripwire');
    ++ $left->{left};
    my $right = $db->root('John');
    $right->{right} = $left->{left};
};
