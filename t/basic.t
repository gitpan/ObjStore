# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'

######################### We start with some black magic to print on failure.

# Change 1..1 below to 1..last_test_to_print .
# (It may become useful if the test is moved to ./t subdirectory.)

sub ok { print "ok $tx\n"; $tx++; }  # this is a dubious aide
sub not_ok { print "not ok $tx\n"; $tx++; }

BEGIN { $| = 1; $tx=1; print "1..7\n"; }
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
    my $DB = ObjStore::Database->open($osdir . "/perltest.db", 0, 0666);
    $DB ? ok : not_ok; #2
    
    try_update {
	my $john = $DB->root('John');

	if (! $john) {
	    my $hv = $DB->newHV('array');
	    ref $hv eq 'ObjStore::HV' ? ok:not_ok;
	    $john = $DB->root('John', $hv);
	    tied(%$john)->Type eq 'HASH' or die $john;
	} else {
	    ok;
	}

	## roots
	
	tied %$john ? ok : not_ok;
	exists $john->{noway} ? not_ok : ok;

	## force OSPV_array to grow

	for (1..10) { $john->{$_} = "String $_"; }

	my $dict = $john->{dict} = $DB->newHV('dict');
	for (1..10) { $dict->{$_} = $_ * 3.14159; }

	## basic counter

	tied(%$john)->Type eq 'HASH' or die $john;

	my $cnt;
	if (exists $john->{cnt}) {
	    $cnt = $john->{cnt};
	} else {
	    $cnt = 'aaa';
	}
	++$cnt;
	$john->{cnt} = $cnt;
#	warn $john->{cnt};

	if ($john->{cnt} ne $cnt) {
	    print "ObjStore: " . join(" ", unpack("c", $john->{cnt})) . "\n";
	    print "perl:     " . join(" ", unpack("c", $cnt)) . "\n";
	    not_ok;
	} else {
	    ok;
	}
    };
    die "[Abort] $@\n" if $@;
    
    ok;
}
exit 0;
