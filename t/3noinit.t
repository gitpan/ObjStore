use Test;
BEGIN { plan test => 6 }

use ObjStore::NoInit;

ok !$ObjStore::INITIALIZED;
ok defined *begin{CODE};

my ($name,$sz) = ("3noinit.t", 6 * 1024 * 1024);
$ObjStore::CLIENT_NAME = $name;
$ObjStore::CACHE_SIZE = $sz;

ObjStore::initialize();

ok $ObjStore::INITIALIZED;
ok $ObjStore::CLIENT_NAME, $name;
ok $ObjStore::CACHE_SIZE, $sz;

eval { ObjStore::NoInit->import(); };
ok $@ =~ m/too late/;
