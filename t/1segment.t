# -*-perl-*-
use Test;
BEGIN { todo test => 7 }

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
    
    $db->get_default_segment_size;
    $db->get_default_segment->set_comment("default segment");
    
    my $empty = $db->create_segment();
    ok($empty->database_of->get_id eq $db->get_id);
    for (qw(as_used read write)) { $empty->set_lock_whole_segment($_); }
    for (qw(segment page stream)) {
	$empty->set_fetch_policy($_, 8192);
    }
    $empty->lock_into_cache;
    $empty->unlock_from_cache;
    $empty->return_memory(1);
    $empty->set_size($empty->size);
    $empty->unused_space;
    ok(! $empty->is_deleted);
    $empty->destroy;
    ok($empty->is_deleted);
    
    if (exists $john->{junk_seg}) {
	delete $john->{junk_in_seg};
    }

    $seg = $db->create_segment();
    $seg->set_comment("junk");
    ok($seg->get_comment eq 'junk');

    $john->{junk_seg} = $seg->get_number();

    my $h = new ObjStore::HV($seg, 10);
    $john->{junk_in_seg} = $h;

    # fill up the segment with junk
    for (keys %$junk) { $h->{$_} = $junk->{$_}; }
    $h->{sptr} = $h->{strs}->new_ref($h, 'hard');
	
    # segment is determined by OSSVPV, not from OSSV
    my $nseg = $h->segment_of;
    ok($nseg->get_number() == $seg->get_number());
    
    # double-check the obvious
    $nseg = $h->{nums}->segment_of;
    ok($nseg->get_number() == $seg->get_number());
};