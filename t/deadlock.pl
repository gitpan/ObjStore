#-*-perl-*-

use ObjStore ':ALL';
set_transaction_priority(0);
set_max_retries(0);
use lib "./t";
use test;

#open(STDOUT, ">>/dev/null") or die "open: $@";
#open(STDERR, ">>/dev/null") or die "open: $@";

&open_db;
begin 'update', sub {
    my $left = $db->root('tripwire');
    ++ $left->{left};
    warn "[2]left\n";

    my $right = $db->root('John');
    $right->{right} = 0;
    $right->{right} = $left->{left};
    warn "[2]right\n";
};
warn "[2]$@" if $@;
