#-*-perl-*-

BEGIN { $| = 1; $tx=1; print "1..1\n"; }

sub ok { print "ok $tx\n"; $tx++; }
sub not_ok { print "not ok $tx\n"; $tx++; }

use ObjStore;

my $db = ObjStore::open(ObjStore->schema_dir . "/perltest.db", 0, 0666);
my $sid;

try_update {
    my $seg = $db->create_segment;
    $sid = $seg->get_number;
    my $h = new ObjStore::HV($seg, 7);
    $db->root("tripwire", $h);
};

try_update {
    $db->destroy_root('tripwire');
};

try_update {
    my $seg = $db->get_segment($sid);
    $seg->is_empty? ok:not_ok;
    $seg->destroy;
};
