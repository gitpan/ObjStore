#-*-perl-*-
BEGIN { $| = 1; $tx=1; print "1..1\n"; }
use ObjStore;
use lib './t';
use test;

&open_db;
try_abort_only {
    my $mess = new ObjStore::HV($db, 'splash_array', 7);
    my $dict = $mess->{dict} = new ObjStore::HV($mess);
    for (1..200) { $mess->{$_} = $_; }
    $dict->{foo} = 'bar';
};
ok;
