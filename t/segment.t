# -*-perl-*-
# Also a good test for reference counting because you can't
# delete a segment that contains any data.

BEGIN { $| = 1; $tx=1; print "1..3\n"; }

sub ok { print "ok $tx\n"; $tx++; }
sub not_ok { print "not ok $tx\n"; $tx++; }

use ObjStore ':ALL';

{
    my $osdir = ObjStore->schema_dir;
    my $DB = ObjStore::open($osdir . "/perltest.db", 0, 0666);
    
    my $junk = {
	'nums' => { 1..50 },
	'strs' => { qw(a b  c d  e f  g h), i => { a => 1 } },
    };

    try_update {
	my $john = $DB->root('John');
	$john ? ok : not_ok;

	my $seg;
	{
	    if (!defined $john->{h1}) {
		$seg = $DB->create_segment();
		$john->{h1} = new ObjStore::HV($seg, 10);
		$john->{seg} = $seg->get_number();
	    } else {
		$seg = $DB->get_segment($john->{seg});
	    }

	    # fill up the segment with junk to test refcnts
	    my $h = $john->{h1};
	    for (keys %$junk) { $h->{$_} = $junk->{$_}; }

	    my $bob = new ObjStore::HV($h, 200);
	    my $dict = new ObjStore::HV($h, 200);
	    $h->{dict} = $dict;
	    my @check;
	    for (1..300) { $dict->{$_} = $bob; }

	    # segment is determined by OSSVPV, not from OSSV
	    my $nseg = ObjStore::Segment::of(tied %{$john->{h1}});
	    $nseg->get_number() == $seg->get_number()? ok : not_ok;
	    
	    # double-check the obvious
	    $nseg = ObjStore::Segment::of(tied %{$john->{h1}{nums}});
	    $nseg->get_number() == $seg->get_number()? ok : not_ok;
	    
	    delete $john->{h1};		# refcnts should go to zero
	}
	$seg->destroy;			# must be empty
    };
}
