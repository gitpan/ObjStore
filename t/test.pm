# Please contribute more better tests!

package test;
use Carp;
use ObjStore;
use ObjStore::Config ':ALL';
require Exporter;
@ISA = 'Exporter';
@EXPORT = qw(&ok &not_ok &test_db &open_db $db);

*tx = *main::tx;

sub test_db() { TMP_DBDIR . "/perltest.db" }

sub ok {
    my ($guess) = @_;
    carp "This is ok $tx" if $guess && $guess != $tx;
    print "ok $tx\n"; $tx++;
}

sub not_ok {
    my ($guess) = @_;
    carp "This is not_ok $tx" if $guess && $guess != $tx;
    print "not ok $tx\n"; $tx++;
}

sub open_db() {
    $db = ObjStore::open(test_db(), 'update');
}

1;
