# note -*-perl-*-
use Test;
BEGIN { plan tests => 10 }

use ObjStore ':ADV';
use lib './t';
use test;

ObjStore::fatal_exceptions(0);

my $nsys = 'ObjStore::Notification';

&open_db;
$nsys->set_queue_size(10);

begin sub {
    my $j = $db->root('John');
    die "no db" if !$j;
    subscribe();   #just testing...
    subscribe($j);
    $j->notify("bonk");
    $j->notify(69, 'now');

    begin sub { $j->notify(69, 'bogus'); };
    ok($@ =~ m/notify/) or warn $@;
    undef $@;
};
die if $@;

begin sub {
    my $n = $nsys->receive();
    ok($n->why == 69);
    my ($sz,$pend,$over) = $nsys->queue_status;
    ok($over == 0);
#    ok($pend == 1); who cares?
    ok($sz == 10);
};
die if $@;

ok($nsys->_get_fd());
my $n = $nsys->receive();

begin sub {
    ok($n->get_database()->get_id eq $db->get_id);
    my $j = $db->root('John');
    ok($n->focus == $j);
    ok($n->why eq 'bonk');
    unsubscribe();
    unsubscribe($j);
    $j->notify("bonk");
};
die if $@;

ok(!defined $nsys->receive(1));
