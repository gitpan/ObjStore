# even obscure -*-perl-*- should work
use Test;
BEGIN { plan tests => 16 }

use ObjStore ':ADV';
use lib './t';
use test;

ok(!defined ObjStore::get_all_servers());

&open_db;

ObjStore::network_servers_available();
ObjStore::get_page_size();
ok(ObjStore::get_n_databases() == 2);  #who cares?

my $s = ObjStore::get_all_servers();
$s->get_host_name();
ok(! $s->connection_is_broken);

for ($s->get_databases) { $_->close; }
$s->disconnect();

ok($s->connection_is_broken);
$s->reconnect();
ok(! $s->connection_is_broken);

for (qw(read mvcc update)) {
    for my $db ($s->get_databases) { 
	$db->close;
	die "open?" if $db->is_open;
	$db->open($_);
	ok($db->is_open eq $_);
    }
}

ok(ObjStore::debug('off') == 0);
ok(ObjStore::release_name() =~ m/ObjectStore/);

$db->get_pathname;
$db->get_relative_directory;
$db->get_sector_size;

begin sub {
    $db->size_in_sectors;
    $db->time_created;
};

$db->set_fetch_policy('segment');
$db->set_fetch_policy('page');
$db->set_fetch_policy('stream', 8192);
eval { $db->set_fetch_policy('bogus'); };
ok($@ =~ m/unrecog/) or warn $@;

for (qw(as_used read write)) { $db->set_lock_whole_segment($_); }
eval { $db->set_lock_whole_segment("bogus"); };
ok($@ =~ m/unrecog/) or warn $@;

ObjStore::return_all_pages();
