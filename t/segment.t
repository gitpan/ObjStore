# -*-perl-*-
BEGIN { $| = 1; $tx=1; print "1..3\n"; }

use ObjStore ':ALL';
use lib './t';
use test;

&open_db;
    
my $junk = {
    'nums' => [ 1..13 ],
    'strs' => { qw(a b  c d  e f  g h), i => [ 'a', 1 ] },
};

begin 'update', sub {
    my $john = $db->root('John');
    die "no db" if !$john;
    
    if (exists $john->{junk_seg}) {
	delete $john->{junk_in_seg};
    }
    $seg = $db->create_segment();
    $john->{junk_seg} = $seg->get_number();

    my $h = new ObjStore::HV($seg, 10);
    $john->{junk_in_seg} = $h;

    # fill up the segment with junk
    for (keys %$junk) { $h->{$_} = $junk->{$_}; }
    $h->{sptr} = $h->{strs}->new_ref($h);
	
    # segment is determined by OSSVPV, not from OSSV
    my $nseg = $h->segment_of;
    ok($nseg->get_number() == $seg->get_number());
    
    # double-check the obvious
    $nseg = $h->{nums}->segment_of;
    ok($nseg->get_number() == $seg->get_number());
};

begin 'update', sub {
    for my $s ($db->get_all_segments) {
	$s->destroy if $s->is_empty;
    }
};
