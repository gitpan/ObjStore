# test all transaction types for -*-perl-*-
BEGIN { $| = 1; $tx=1; print "1..8\n"; }

use strict;
use ObjStore ':ALL';
use ObjStore::Config;
use lib './t';
use test;

ObjStore::fatal_exceptions(0);
ObjStore::set_transaction_priority(0);

&open_db;

eval { &ObjStore::lookup(TMP_DBDIR . "/bogus.db", 0); };
ok($@ =~ m/does not exist/) or warn $@;

# make sure the tripwire is ready
begin 'update', sub {
    $db->root("tripwire", sub {new ObjStore::HV($db->create_segment, 7)});
};
die if $@;

begin 'update', sub {
    my $john = $db->root('John');
    $john->{right} = 69;
};

begin('read', sub {
    my $john = $db->root('John');
    
    eval { $john->{'write'} = 0; };
    ok($@ =~ m/Attempt to write during a read-only/) or warn $@;

    ok($john->{right} == 69);
});
ok(! $@);

begin('update', sub {
    my $j = $db->root('John');
    begin('update', sub {
	$j->{oopsie} = [1,2];
	die 'undo';
    });
    warn $@ if $@ !~ m'^undo';
    ok(! exists $j->{oopsie});
});
ok(! $@);

if (1) {
#ObjStore::debug qw(txn);
my $debug =0;

# retry deadlock
set_max_retries(10);
my $retry=0;
my $attempt=0;
begin 'update', sub {
    ++ $retry;

    my $right = $db->root('John');
    ++ $right->{right};
    warn "[1]right\n" if $debug;

    my $code = sub {
	warn "begin bogus code" if $debug;
	my $quiet = 1? '2>/dev/null':'';
	system("perl -Mblib t/deadlock.pl 1>/dev/null $quiet &");
	warn "[1]sleep\n" if $debug;
	sleep 5;
	warn "[1]left\n" if $debug;
	my $left = $db->root('tripwire');
	$left->{left} = 0;
	$left->{left} = $right->{right};
    };
    ++ $attempt;
    warn "attempt $attempt retry $retry" if $debug;
    if ($attempt == 1) {
	&$code;
	die "Didn't get deadlock";
    } elsif ($attempt == 2) {
	begin 'update', \&$code;
	die if $@;
    } else { 1 }
};
warn $@ if $@;
ok($attempt==3) or warn $attempt;
}
