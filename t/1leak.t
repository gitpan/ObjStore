# -*-perl-*- never leaks memory...

use strict;
use Test;
eval { require Devel::Leak } or do {
    plan test => 1;
    warn "Devel::Leak unavailable\n";
    exit;
};

plan test => 2;
use ObjStore;
use lib './t';
use test;

&open_db;

for (1..2) {
    begin sub {
	my $j = $db->root('John');
    };
    die if $@;
}

use vars qw($snapshot);
my $count = Devel::Leak::NoteSV($snapshot);

for (1..2) {
    begin sub {
	my $j = $db->root('John');
    };
    die if $@;
}

ok Devel::Leak::CheckSV($snapshot), $count;
