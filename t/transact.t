# test all transaction types for -*-perl-*-
BEGIN { $| = 1; $tx=1; print "1..9\n"; }

use strict;
use ObjStore ':ALL';
use ObjStore::Config;
use lib './t';
use test;

ObjStore::rethrow_exceptions(0);
ObjStore::set_transaction_priority(0);

&open_db;

if (1) {
eval { my $b = ObjStore::lookup(TMP_DBDIR . "/bogus.db", 0); };
$@ =~ m/does not exist/ ? ok: do {not_ok; warn $@;};

# make sure the tripwire is ready
try_update {
    $db->root("tripwire", sub {new ObjStore::HV($db->create_segment, 7)});
};
die if $@;

my @ret = try_update {
    my $john = $db->root('John');
    $john->{right} = 69;
    qw(void context for now);
};
@ret ? not_ok : ok;

begin('read', sub {
    my $john = $db->root('John');
    
    eval { my $b = ObjStore::lookup(TMP_DBDIR . "/bogus.db", 0); };
    $@ =~ m/does not exist/ ? ok: do {not_ok; warn $@;};

    eval { $john->{'write'} = 0; };
    $@ =~ m/Attempt to write during a read-only/ ? ok : not_ok;

    $john->{right} == 69? ok : not_ok;
});
$@ ? not_ok:ok;
}

if (1) {
begin('update', sub {
    my $j = $db->root('John');
    begin('update', sub {
	$j->{oopsie} = [1,2];
	die 'undo';
    });
    warn $@ if $@ !~ m'^undo';
    exists $j->{oopsie}? not_ok : ok;
});
$@ ? not_ok : ok;
}

if (1) {
#ObjStore::debug qw(txn);
my $debug =0;

# retry deadlock
set_max_retries(10);
my $retry=0;
my $attempt=0;
try_update {
    ++ $retry;

    my $right = $db->root('John');
    ++ $right->{right};
    warn "[1]right\n" if $debug;

    my $code = sub {
	warn "begin bogus code" if $debug;
	my $quiet = 1? '2>/dev/null':'';
	system("perl -Mblib t/deadlock.pl $quiet &");
	warn "[1]sleep\n" if $debug;
	sleep 5;
	warn "[1]left\n" if $debug;
	my $left = $db->root('tripwire');
	$left->{left} = 0;
	$left->{left} = $right->{right};
    };
    ++ $attempt;
#    warn "attempt $attempt retry $retry";
    if ($attempt == 1) {
	&$code;
	die "Didn't get deadlock";
    } elsif ($attempt == 2) {
	eval { &$code };
	die if $@;
    } elsif ($attempt == 3) {
	try_update(\&$code);
	die if $@;
    } else { 1 }
};
warn $@ if $@;
if ($attempt==4) {ok}
else {warn $attempt; not_ok; }
}
