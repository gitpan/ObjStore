# Please feel free to contribute more better tests!

package test;
#use Carp qw(verbose carp croak);
use Carp;
use Test;
use ObjStore;
use ObjStore::Config ':ALL';
require Exporter;
@ISA = 'Exporter';
@EXPORT = qw(&test_db &open_db $db);

#ObjStore::debug qw(txn);
#$ObjStore::REGRESS = 1;

$SIG{__WARN__} = sub {
    my $m = $_[0];
    if ($m !~ m/ line \s+ \d+ (\.)? $/x) {
	warn $m;
    } else {
	print "# [WARNING] $_[0]"; #hide from Test::Harness
    }
};

sub test_db() { TMP_DBDIR . "/perltest" }

sub open_db() {
    $db = ObjStore::open(test_db(), 'update');
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
    ok($ok);
}

1;
