# This is obviously -*-perl-*- dontcha-think?

BEGIN { $| = 1; $tx=1; print "1..2\n"; }
sub ok { print "ok $tx\n"; $tx++; }
sub not_ok { print "not ok $tx\n"; $tx++; }

package main;
use strict;
use ObjStore;
use lib "./t";

my $osdir = ObjStore->schema_dir;
my $DB = ObjStore::open($osdir . "/perltest.db", 0, 0666);
    
try_update {
    require PTest;

    my $john = $DB->root('John');
    $john ? ok : not_ok;
    
    $john->{obj} = new PTest($DB);
};

try_update {
    my $john = $DB->root('John');
    $john->{obj}->bonk ? ok : not_ok;
};
