# set -*-perl-*-
BEGIN { $| = 1; $tx=1; print "1..7\n"; }

use strict;
use ObjStore;
use lib './t';
use test;

#ObjStore::_debug qw(bridge);
#ObjStore::disable_auto_class_loading();

&open_db;
for my $rep (10, 100) {
    try_update {
	my $john = $db->root('John');
	die "No database" if !$john;
    
	my $set = $john->{c} = new ObjStore::Set($db, $rep);
	$set->add({ joe => 1 }, { bob => 2 }, { ed => 3 });

	my (@k,@v,@set);
	for (my $o = $set->first; $o; $o = $set->next) {
	    push(@set, $o);
	    push(@k, keys %$o);
	    for (values %$o) { push(@v, $_); }
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

	my $yuk = pop @set;
	$set->rm($yuk);
	$set->contains($yuk) ? not_ok : ok;
	$set->add($yuk);
	$set->contains($yuk) ? ok : not_ok;
    };
};