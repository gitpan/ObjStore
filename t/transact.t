# test all transaction types for -*-perl-*-
BEGIN { $| = 1; $tx=1; print "1..4\n"; }

use strict;
use ObjStore ':ALL';
use lib './t';
use test;

rethrow_exceptions(0);
set_transaction_priority(0);

&open_db;
my @ret = try_update {
    my $john = $db->root('John');
    die "No db" if !$john;
    
    $john->{right} = 69;

    'void context';
};
@ret ? not_ok : ok;

try_abort_only {
    my $john = $db->root('John');
    $john->{right} = 3;
};

try_read {
    my $john = $db->root('John');
    
    if (0) {
	# NESTED EVAL BROKEN
	reval(sub {
	    my $b = ObjStore::lookup("bogus.db");
	    warn $b;
	});
	warn $@;
	$@ ? ok:not_ok;
    }

    $john->{right} == 69? ok : not_ok;

    $john->{'write'} = 0;
};
if ($@) { warn $@ if $@ !~ m/Attempt to write during a read-only/; ok }
else { not_ok; warn $@; }

#ObjStore::_debug qw(deadlock);

# retry deadlock
try_update {
    $db->root("tripwire", sub {new ObjStore::HV($db->create_segment, 7)});
};
die if $@;
set_max_retries(10);
my $attempt=0;
try_update {
    ++ $attempt;

    my $right = $db->root('John');
    ++ $right->{right};

    my $code = sub {
#	warn "begin bogus code";
	system("perl -Mblib t/deadlock.pl 2>/dev/null &");
	sleep 3;
#	warn "pre-deadlock";
	my $left = $db->root('tripwire');
	$left->{left} = $right->{right};
    };
#    warn "attempt $attempt";
    if ($attempt == 1) {
	&$code;
    } elsif ($attempt > 1) {
	# fall through
    } elsif ($attempt == 2) {
	die 'not yet';
	reval { &$code };
#	warn $@;
	die if $@;
    } elsif ($attempt == 3) {
	die 'not yet';
	try_update(\&$code);
	warn $@;
	die if $@;
    } else { die "what?" }
};
warn $@ if $@;
if ($attempt==3) {ok}
else {warn $attempt; not_ok; }
