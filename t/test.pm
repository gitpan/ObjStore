# Please contribute more better tests!

package test;
use Exporter;
use ObjStore;
use ObjStore::Config ':ALL';
@ISA = 'Exporter';
@EXPORT = qw(&ok &not_ok &test_db &open_db $db);

*tx = *main::tx;

sub test_db() { TMP_DBDIR . "/perltest.db" }

sub ok { print "ok $tx\n"; $tx++; }  # this is a dubious aide

sub not_ok { print "not ok $tx\n"; $tx++; }

sub open_db() {
    $db = ObjStore::open(test_db(), 0);
}

1;
