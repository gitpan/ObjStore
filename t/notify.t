# note -*-perl-*-
BEGIN { $| = 1; $tx=1; print "1..5\n"; }

use ObjStore ':ADV';
use lib './t';
use test;

&open_db;
begin sub {
    my $j = $db->root('John');
    die "no db" if !$j;
    subscribe($j);
    $j->notify("bonk");
    $j->notify(69, 'now');
};

begin sub {
    my $n = ObjStore::Notification->receive();
    ok($n->why == 69);
};

my $n = ObjStore::Notification->receive();

begin sub {
    ok($n->get_database()->get_id eq $db->get_id);
    my $j = $db->root('John');
    ok($n->focus == $j);
    ok($n->why eq 'bonk');
};
