# test all transaction types and nested transactions

BEGIN { $| = 1; $tx=1; print "1..4\n"; }

sub ok { print "ok $tx\n"; $tx++; }
sub not_ok { print "not ok $tx\n"; $tx++; }

use strict;
use ObjStore;

my $DB = ObjStore::Database->open(ObjStore->schema_dir . "/perltest.db", 0, 0666);

{
    try_update {
	my $john = $DB->root('John');
	$john ? ok : not_ok;

	exists $john->{right}? not_ok : ok;

	$john->{right} = 69;

	try_update {
	    $john->{right} = 2;
	    die 'wrong';
	};
	'yes';
    };
    warn $@ if $@;

    try_abort_only {
	my $john = $DB->root('John');
	$john->{right} = 3;
	(1,'two');
    };

    try_read {
	my $john = $DB->root('John');
	
	if ($john->{right} == 69) { ok; }
	else { not_ok; warn $john->{right}; }

	$john->{'write'} = 0;
    };
    if ($@) { ok }
    else { not_ok; warn $@; }

    try_update {
	my $john = $DB->root('John');
	delete $john->{right};
    };
}
