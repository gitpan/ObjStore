#-*-perl-*-
BEGIN { $| = 1; $tx=1; print "1..6\n"; }

use ObjStore;
use lib './t';
use test;

&open_db;

my $sid;

try_update {
    my $seg = $db->create_segment;
    $sid = $seg->get_number;
    $db->root("tripwire", [1,2,3,'Oops, tripped!']);
};

try_update {
    $db->destroy_root('tripwire');

    my $rt = $db->find_root('_osperl_private');
    $rt? not_ok : ok;
    $rt = $db->_PRIVATE_ROOT();
    $rt? ok : not_ok;
    $rt = $db->find_root('_osperl_private');
    $rt? not_ok : ok;
};

try_update {
    my $seg = $db->get_segment($sid);
    $seg->is_empty? ok:not_ok;
    $seg->destroy;
};

try_update {
    my $ok=1;
    for ($db->get_all_roots()) {
	$ok=0 if $_->get_name eq '_osperl_private';
    }
    $ok? ok:not_ok;
};
