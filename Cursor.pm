package ObjStore::Cursor;	# simply a stack of cursors
use strict;
use Carp;
use ObjStore;
use vars qw(@ISA);
require ObjStore::Ref;
@ISA = 'ObjStore::Ref';

sub Push {
    my ($o, $loc) = @_;
    if ($loc->isa("ObjStore::Database")) {
	# create cursors to all the roots
	my %roots = (map {$_->get_name(), $_->get_value()->new_cursor($o)}
		     $loc->get_all_roots());

	my $rmap = ObjStore::translate($o, \%roots);
	while ($o->depth) { $o->_Pop };
	$o->_Push($rmap->new_cursor($o));
    } else {
	$o->_Push($loc->new_cursor($o));
    }
}

# Do something reasonable if the stack is made of Cursors.

sub seek_pole {
    my ($o, $side) = @_;
    croak "Cursor unset" if $o->depth == 0;
    croak "Can't seek to end yet" if $side eq 'end';
    my $cs = $o->[$o->depth -1];
    $cs->seek_pole(0);
}

sub at {
    my ($o) = @_;
    croak "Cursor unset" if $o->depth == 0;
    my $cs = $o->[$o->depth -1];
    $cs->at;
}

sub next {
    my ($o) = @_;
    croak "Cursor unset" if $o->depth == 0;
    my $cs = $o->[$o->depth -1];
    $cs->next;
}

1;
