package ObjStore::Path::Ref;
use strict;
use Carp;
use ObjStore;
use base 'ObjStore::AV';

sub new {
    my ($this, $where) = @_;
    my $class = ref($this) || $this;
    my $o = $class->SUPER::new($where);
    $o;
}

sub open {
    my ($o, $how) = @_;
    my $cnt = $o->_count;
    for (my $x=0; $x < $cnt; $x++) {
	my $db = $o->[$x]->get_database();
	$db->open($how) or die "$db->open: $@";
    }
}

sub depth { my ($o) = @_; $o->_count; }

sub focus {
    my ($o, $xx) = @_;
    croak "Cursor unset" if $o->depth == 0;
    $xx = $o->depth - 1 if !defined $xx;
    $o->[$xx]->focus;
}

1;
