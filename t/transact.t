# test all transaction types and nested transactions in -*-perl-*-

BEGIN { $| = 1; $tx=1; print "1..5\n"; }

sub ok { print "ok $tx\n"; $tx++; }
sub not_ok { print "not ok $tx\n"; $tx++; }

use strict;
use ObjStore ':ALL';
set_transaction_priority(0);

my $db = ObjStore::open(&schema_dir . "/perltest.db", 0, 0666);

try_update {
    my $john = $db->root('John');
    $john ? ok : not_ok;
    
    exists $john->{right}? not_ok : ok;
    
    $john->{right} = 69;
    
    'yes';
};
warn $@ if $@;

try_abort_only {
    my $john = $db->root('John');
    $john->{right} = 3;
    (1,'two');
};

try_read {
    my $john = $db->root('John');
    
    if ($john->{right} == 69) { ok; }
    else { not_ok; warn $john->{right}; }
    
    $john->{'write'} = 0;
};
if ($@) { ok }
else { not_ok; warn $@; }

# abort_top_level
try_update {
    my $john = $db->root('John');
    try_update {
	++ $john->{right};
        abort_top_level();
    };
    warn $@ if $@;
    not_ok;
};
ok if $@ =~ m/abort_top_level/;  #5

# retry deadlock
try_update { $db->root("tripwire", new ObjStore::HV($db->create_segment, 7)); };
die if $@;
set_max_retries(2);
my $attempt=0;
try_update {
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
    ++ $attempt;
#    warn "attempt $attempt";
    if ($attempt == 1) {
	&$code;
    } elsif ($attempt == 2) {
	eval { &$code };
#	warn $@;
	die if $@;
    } elsif ($attempt == 3) {
	# INFINITE LOOP!
	try_update(\&$code);
	warn $@;
	die if $@;
    } else { die "what?" }
};
$attempt==2? ok:not_ok;

try_update {
    my $john = $db->root('John');
    delete $john->{right};
};
