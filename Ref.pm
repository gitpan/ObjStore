package ObjStore::Ref;	# simply a stack of refs
use strict;
use Carp;
use ObjStore;
use vars qw(@ISA);
@ISA = 'ObjStore::AV';

sub new {
    my ($this, $where) = @_;
    my $class = ref($this) || $this;
    my $o = $class->SUPER::new($where);
    $o;
}

# This will break if you osrm the referred-to database, and you can't call
# it within an eval either.  (Transactions are broken)
sub open {
    my ($o, $how) = @_;
    my $cnt = $o->_count;
    for (my $x=0; $x < $cnt; $x++) {
	my $db = $o->[$x]->get_database();
	$db->open($how);
	$db->sync_INC();
    }
}

sub depth { my ($o) = @_; $o->_count; }

sub focus {
    my ($o, $xx) = @_;
    croak "Cursor unset" if $o->depth == 0;
    $xx = $o->depth - 1 if !defined $xx;
    $o->[$xx]->focus;
}

sub Pop {
    my ($o) = @_;
    $o->_Pop;
}

sub Push {
    my ($o, $loc) = @_;
    if ($loc->isa("ObjStore::Database")) {
	# create cursors to all the roots
	my %roots = (map {$_->get_name(), $_->get_value()->new_ref($o)}
		     $loc->get_all_roots());

	my $rmap = ObjStore::translate($o, \%roots);
	while ($o->depth) { $o->Pop };
	$o->_Push($rmap->new_ref($o));
    } else {
	$o->_Push($loc->new_ref($o));
    }
}

1;
