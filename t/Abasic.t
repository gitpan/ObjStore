# -*-perl-*-
# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'

######################### We start with some magic to print on failure...

BEGIN { $| = 1; $tx=1; print "1..7\n"; }
END {print "not ok 1\n" unless $loaded;}

use ObjStore;
use lib './t';
use test;

#ObjStore::debug 'PANIC';

$loaded = 1; ok(1);

$db = ObjStore::open(&test_db, 0, 0666) or die $@;
ok($db);

begin 'update', sub {
    my $john = $db->root('John');
    if (! $john) {
	my $hv = new ObjStore::HV($db, 'splash_array', 7);
	$john = $db->root('John', $hv);
    }
    ok(ref $john eq 'ObjStore::HV') or do {
	print "perl: " . join(" ", unpack("c*", 'ObjStore::HV')) . "\n";
	print "ObjStore: " . join(" ", unpack("c*", ref($john))) . "\n";
    };
    
    ## roots
    ok(tied %$john);
    ok(! exists $john->{noway});
    
    ## force OSPV_array to grow
    for (1..10) { $john->{$_} = "String $_"; }
    
    $john->{dict} = new ObjStore::HV($db, 'os_dictionary', 20);
    my $dict = $john->{dict};
    for (1..10) { $dict->{$_} = $_ * 3.14159; }
    
    ## strings work?
    my $pstr = pack('c4', 65, 66, 0, 67);
    $john->{packed} = $pstr;
    ok($john->{packed} eq $pstr) or do {
	print "ObjStore: " . join(" ", unpack("c*", $john->{packed})) . "\n";
	print "perl:     " . join(" ", unpack("c*", $pstr)) . "\n";
    };
    delete $john->{packed};
};
