# -*-perl-*-
# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'

######################### We start with some black magic to print on failure.

BEGIN { $| = 1; $tx=1; print "1..8\n"; }
END {print "not ok 1\n" unless $loaded;}

use ObjStore;
use lib './t';
use test;

#ObjStore::debug 'PANIC';

$loaded = 1; ok; #1

$db = ObjStore::open(&test_db, 0, 0666) or die $@;
$db? ok : not_ok; #2

begin 'update', sub {
    my $john = $db->root('John');
    if (! $john) {
	my $hv = new ObjStore::HV($db, 'splash_array', 7);
	$john = $db->root('John', $hv);
    }
    
    if (ref $john eq 'ObjStore::HV') {ok}
    else {
	print "perl: " . join(" ", unpack("c*", 'ObjStore::HV')) . "\n";
	print "ObjStore: " . join(" ", unpack("c*", ref($john))) . "\n";
	not_ok;
    }
    
    ## roots
    tied %$john ? ok : not_ok;
    exists $john->{noway} ? not_ok : ok;
    
    ## force OSPV_array to grow
    for (1..10) { $john->{$_} = "String $_"; }
    
    $john->{dict} = new ObjStore::HV($db, 'os_dictionary', 20);
    my $dict = $john->{dict};
    for (1..10) { $dict->{$_} = $_ * 3.14159; }
    
    ## strings work?
    my $pstr = pack('c4', 65, 66, 0, 67);
    $john->{packed} = $pstr;
    if ($john->{packed} eq $pstr) {
	ok;
    } else {
	print "ObjStore: " . join(" ", unpack("c*", $john->{packed})) . "\n";
	print "perl:     " . join(" ", unpack("c*", $pstr)) . "\n";
	not_ok;
    }
    delete $john->{packed};
};

ok;
