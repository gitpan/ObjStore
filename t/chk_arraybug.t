#-*-perl-*-

BEGIN { $| = 1; $tx=1; print "1..1\n"; }
sub ok { print "ok $tx\n"; $tx++; }
sub not_ok { print "not ok $tx\n"; $tx++; }
use ObjStore;

my $osdir = ObjStore->schema_dir;
my $DB = ObjStore::Database->open($osdir . "/perltest.db", 0, 0666);

try_abort_only {
    my $mess = new ObjStore::HV($DB, 'array');
    my $dict = $mess->{dict} = new ObjStore::HV($mess);
    for (1..200) { $mess->{$_} = $_; }
    $dict->{foo} = 'bar';
};
die if $@;
ok;
