# Please contribute more better tests!

package test;
use Carp;
use ObjStore;
use ObjStore::Config ':ALL';
require Exporter;
@ISA = 'Exporter';
@EXPORT = qw(&ok &not_ok &test_db &open_db $db);

#ObjStore::debug qw(txn);
#$ObjStore::REGRESS = 1;
*tx = *main::tx;

sub test_db() { TMP_DBDIR . "/perltest" }

sub ok {
    my ($guess) = @_;
    carp "This is ok $tx" if $guess && $guess != $tx;
    print "ok $tx\n"; $tx++;
}

sub not_ok {
    my ($guess) = @_;
    carp "This is not_ok $tx" if $guess && $guess != $tx;
    warn $@ if $@;
    print "not ok $tx\n"; $tx++;
}

sub open_db() {
    $db = ObjStore::open(test_db(), 'update') or die $@;
    die if $@; #extra paranoia
    $db;
}

END { 
#    $db->close;
    
    my $ok=1;
   if (0) {
    use IO::Pipe;
    $pipe = new IO::Pipe;
    $pipe->reader("osverifydb", TMP_DBDIR . "/perltest");
    while (defined(my $l = <$pipe>)) {
	if ($l =~ /illegal value/) {
	    print $l;
	    $ok=0;
	}
    }
}
    $ok? ok:not_ok;
}

1;
