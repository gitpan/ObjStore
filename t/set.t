# set -*-perl-*-

BEGIN { $| = 1; $tx=1; print "1..2\n"; }
sub ok { print "ok $tx\n"; $tx++; }
sub not_ok { print "not ok $tx\n"; $tx++; }

use strict;
use ObjStore;

my $DB = ObjStore::Database->open(ObjStore->schema_dir . "/perltest.db", 0, 0666);

for my $rep (qw(array hash)) {
    try_update {
	my $john = $DB->root('John');
	die if !$john;
    
	my $set = $john->{c} = new ObjStore::Set($DB, $rep);
	$set->a({ joe => 1 }, { bob => 2 }, { ed => 3 });

	my (@k,@v);
	for (my $o = $set->first; $o; $o = $set->next) {
	    push(@k, keys %$o);
	    push(@v, values %$o);
	}
	@k = sort @k;
	@v = sort @v;
	if (@k==3 and $k[0] eq 'bob' and $k[1] eq 'ed' and $k[2] eq 'joe' and
	    @v==3 and $v[0] == 1 and $v[1] == 2 and $v[2] == 3) {
	    ok;
	} else {
	    not_ok;
	    warn join(' ', @k);
	    warn join(' ', @v);
	}
	delete $john->{c};
    }
};
print "[Abort] $@\n" if $@;
