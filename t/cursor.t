BEGIN { $| = 1; $tx=1; print "1..5\n"; }

sub ok { print "ok $tx\n"; $tx++; }
sub not_ok { print "not ok $tx\n"; $tx++; }

use ObjStore;

$DB = ObjStore::Database->open(ObjStore->schema_dir . "/perltest.db", 0, 0666);

sub chk1 {
    my ($john, $rep) = @_;

    my $ok=1;
    
    my $ah = $john->{$rep} = $DB->newHV($rep);
    for (1..8) { $ah->{$_} = 1; }

    my @k = sort keys %$ah;
    @k == 8 or $ok=0;
    for (my $x=1; $x <= 8; $x++) {
	$k[$x-1] == $x or $ok=0;
    }
    $ok? ok : not_ok;
    
    delete $ah->{3};
    @k = sort keys %$ah;
    for (my $x=0; $x < @k; $x++) {
	$k[$x] == ($x >= 2? $x+2 : $x+1) or $ok=0;
    }
    $ok? ok : not_ok;
}

{
    try_update {
	my $john = $DB->root('John');
	$john ? ok : not_ok;

	chk1($john, 'array');
	chk1($john, 'dict');
    };
    print "[Abort] $@\n" if $@;
}
