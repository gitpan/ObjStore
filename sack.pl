BEGIN { $| = 1; $tx=1; print "1..5\n"; }

sub ok { print "ok $tx\n"; $tx++; }
sub not_ok { print "not ok $tx\n"; $tx++; }

use ObjStore;

$DB = ObjStore::Database->open(ObjStore->schema_dir . "/perltest.db", 0, 0666);

{
    try_update {
	my $john = $DB->root('John');
	$john ? ok : not_ok;

	$john->{s} = $DB->newSack('array') if !$john->{s};

	my $h = $DB->newTiedHV('array');
	$h->{dt} = localtime;
	$john->{s}->a($h);

	my $sack = $john->{s};
	for (my $e=$sack->first; $e; $e=$sack->next) {
	    my $nuke=1;
	    for my $x (1..5) {
		if (!defined $e->{$x}) {
		    print "$e->{dt} => $x\n";
		    $e->{$x} = 1;
		    $nuke=0;
		    last;
		}
	    }
	    if ($nuke) {
		print "nuke $e->{dt}\n";
		$sack->r($e);
	    }
	}
    };
    print "[Abort] $@\n" if $@;
}
