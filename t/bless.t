# This is obviously -*-perl-*- don'tcha-think?
BEGIN { $| = 1; $tx=1; print "1..4\n"; }

use strict;
use ObjStore;
use lib "./t";
use test;

&open_db;
try_update {
    require PTest;

    my $john = $db->root('John');
    $john ? ok : not_ok;
    
    $john->{obj} = new PTest($db);
    ref($john->{obj}) eq 'PTest'? ok:not_ok;
};

try_update {
    my $john = $db->root('John');
    my $o = $john->{obj};
    ref($o) eq 'PTest'? ok:not_ok;
    $o->bonk ? ok : not_ok;
};
