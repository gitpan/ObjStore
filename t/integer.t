#-*-perl-*-
BEGIN { $| = 1; $tx=1; print "1..1\n"; }

use strict;
use ObjStore ':ALL';
use lib './t';
use integer;
use test;

&open_db;
try_update {
    my $john = $db->root('John');
    my $fatty = $john->{'fatty'} ||= new ObjStore::AV($db, 100);

    my $ok=1;
    for my $x (0..90) {
	$fatty->[$x] = $x + 32760;
	$ok &&= $fatty->[$x] == $x + 32760;
    }
    $ok? ok:not_ok;
};
