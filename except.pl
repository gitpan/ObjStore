#./blib/bin/osperl -Mblib except.pl 

use ObjStore;

$DB = ObjStore::Database->open(ObjStore->schema_dir . "/perltest.db", 0, 0666);

{
    {
	try_read {
	    my $john;
	    $john = $DB->newHV('array');
	};
	print "[Abort] $@\n" if $@;
    };
    print "[Done] $@\n" if $@;
    print "john finalized\n";
}
