#-*-perl-*-
BEGIN { $| = 1; $tx=1; print "1..1\n"; }

use strict;
use ObjStore ':ALL';
use lib './t';
use test;

#ObjStore::_debug qw(refcnt);

&open_db;
try_update {
    # Try to write the same thing in 1 line in C++...   :-)
    $db->root('weakref', translate($db, [1..2, {'abc'=>'quagmire'}])->new_cursor);
};

try_read {
    my $j = $db->root('weakref');
    $j->deleted ? ok:not_ok;
};

try_update {
    $db->find_root('weakref')->destroy;
};
