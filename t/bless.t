# This is obviously -*-perl-*- don'tcha-think?
BEGIN { $| = 1; $tx=1; print "1..7\n"; }

use strict;
use ObjStore;
use lib './t';
use test;

require TestDB;
$db = new TestDB(test_db(), 'update');
$db->isa('TestDB')? ok:not_ok;

try_update {
    $db->get_INC->[0] = "./t";
    $db->sync_INC;
    require PTest;

    my $john = $db->root('John');
    $john ? ok : not_ok;
    
    my $phash = {};
#    warn $phash;
    my $p1 = bless $phash, 'PTest';
    ref $p1 eq 'PTest' ? ok : do { not_ok; warn $p1; };
    
    $john->{obj} = $p1;
    ref $john->{obj} eq 'PTest' ? ok: do { not_ok; warn $john->{obj}; };

    $john->{obj} = new PTest($db);
    ref $john->{obj} eq 'PTest'? ok:not_ok;
};

try_update {
    my $john = $db->root('John');
    my $o = $john->{obj};
    ref($o) eq 'PTest'? ok:not_ok;
    $o->bonk ? ok : not_ok;
};
