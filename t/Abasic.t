# -*-perl-*-
# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'

######################### We start with some black magic to print on failure.

# Change 1..1 below to 1..last_test_to_print .
# (It may become useful if the test is moved to ./t subdirectory.)

sub ok { print "ok $tx\n"; $tx++; }  # this is a dubious aide
sub not_ok { print "not ok $tx\n"; $tx++; }

BEGIN { $| = 1; $tx=1; print "1..8\n"; }
END {not_ok unless $loaded;}
use ObjStore;
$loaded = 1;
ok; #1

######################### End of black magic.

# Insert your test code below (better if it prints "ok 13"
# (correspondingly "not ok 13") depending on the success of chunk 13
# of the test code):

{
    my $osdir = ObjStore->schema_dir;
    my $DB = ObjStore::open($osdir . "/perltest.db", 0, 0666);
    $DB ? ok : not_ok; #2
    
    try_update {
	my $john = $DB->root('John');

	if (! $john) {
	    my $hv = new ObjStore::HV($DB, 'splash_array', 7);
	    $john = $DB->root('John', $hv);
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

	$john->{dict} = new ObjStore::HV($DB, 'os_dictionary', 20);
	my $dict = $john->{dict};
	for (1..10) { $dict->{$_} = $_ * 3.14159; }

	## basic counter

	my $cnt;
	if (exists $john->{cnt}) {
	    $cnt = $john->{cnt};
	} else {
	    $cnt = 'aaa';
	}
	++$cnt;
#	warn $cnt;
	$john->{cnt} = $cnt;
	$john->{cnt} eq $john->FETCH('cnt') or die "oops";

	# null termination is stripped
	my $pstr = pack('c4', 65, 66, 67, 0);
	$john->{packed} = $pstr;
	if ($john->{packed} eq $pstr) {
	    print "ObjStore: " . join(" ", unpack("c*", $john->{packed})) . "\n";
	    print "perl:     " . join(" ", unpack("c*", $pstr)) . "\n";
	    not_ok;
	} else {
	    ok;
	}

	# should be exact
	if ($john->{cnt} ne $cnt) {
	    print "ObjStore: " . join(" ", unpack("c*", $john->{cnt})) . "\n";
	    print "perl:     " . join(" ", unpack("c*", $cnt)) . "\n";
	    not_ok;
	} else {
	    ok;
	}
    };
    die "[Abort] $@\n" if $@;
    
    ok;
}
exit 0;
