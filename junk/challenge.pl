#!./perl

# SQL Challenge
#
# 1. Create a new database or use the existing one.
# 2. Populate a table with questions.
# 3. Print them out in the general pattern: 1 1,2 1,2,3 ...

use ObjStore;
use ObjStore::Config;

my $db = ObjStore::open(TMP_DBDIR . "/challenge", 'update', 0666);

begin 'update', sub {
    $db->root('questions' => sub { 
		  my $i = new ObjStore::Index($db);
		  $i->configure(path => 'msg', unique => 1);

		  $i->add({ msg => "Do you want some orange juice?" });
		  $i->add({ msg => "Are you hungry?" });
		  $i->add({ msg => "How are you today?" });
		  $i->add({ msg => "SQL is the best language ever!" });
		  $i;
	      });
};

begin sub {
    my $c = $db->root('questions')->new_cursor;
    for (my $e=1; $e <= $c->count; $e++) {
	$c->moveto(-1);
	for (1..$e) { print $c->each(1)->{msg}."\n"; }
	print "\n";
    }
};
