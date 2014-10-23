# -*-perl-*-
# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'

######################### We start with some magic to print on failure...

use Test;
BEGIN { plan tests => 5 }
END { ok($loaded);}

use ObjStore;
$loaded = 1;

use lib './t';
use test;

#$ObjStore::REGRESS = 1;
#ObjStore::debug 'PANIC';
#ObjStore::debug 'txn';

$db = ObjStore::open(&test_db, 0, 0666);
ok($db);

begin 'update', sub {
    my $john = $db->root('John');

    if (! $john) {
	my $hv = new ObjStore::HV($db, 7);
	$john = $db->root('John', $hv);
    }

    ok(ref $john eq 'ObjStore::HV') or do {
	print "perl: " . join(" ", unpack("c*", 'ObjStore::HV')) . "\n";
	print "ObjStore: " . join(" ", unpack("c*", ref($john))) . "\n";
    };
    
    ## roots
    ok(tied %$john);
};
