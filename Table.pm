# Simulated RDBMS tables :-) :-)
#
# Oops, but you can store rows in multiple tables (or nest tables)
# Oops, but you can create indices keyed off of a perl sub...
# Oops, but you can ...
#
# Completely optional, of course.
#
use strict;  #lexical?

# Tied array where adds/deletes can trigger index updates
package ObjStore::Table;
use Carp;
use ObjStore;
use base 'ObjStore::HV';

sub new {
    my ($class, $where, $size) = @_;
    croak "$class\->new(where, size)" if @_ != 3;
    my $o = $class->SUPER::new($where);
    my $seg = $o->database_of->create_segment;
    $seg->set_comment("table cluster");
    $o->{array} = new ObjStore::AV($seg, $size);
    $o->{indices} = {};
    $o;
}

sub array { $_[0]->{array}; }

sub index { $_[0]->{indices}{$_[1]}; }  #no check...? XXX

sub new_index {
    my ($o, $type, @REST) = @_;
    my $class = 'ObjStore::Table::Index::'.$type;
    $o->add_index($class->new($o, @REST));
}

sub add_index {
    my ($o, $index) = @_;
    $o->{indices}{ $index->name } = $index;
}

sub indices {
    my ($o) = @_;
    keys %{$o->{indices}};
}

sub remove_index {
    my ($o, $name) = @_;
    die "$o->remove_index($name): index doesn't exist"
	if !exists $o->{'indices'}{ $name };
    delete $o->{'indices'}{ $name };
}

sub NOREFS {
    my $o = shift;
    delete $o->{'indices'};
}

# Should be able to build indices all at once or incrementally
package ObjStore::Table::Index;
use ObjStore;
use base 'ObjStore::HV';

# An index should be autonomous and do it's own clustering.
sub new {
    my ($class, $table, $name) = @_;
    my $o = $class->SUPER::new($table);
    $o->{_table} = $table->new_ref;
    $o->{_name} = $name;
    $o;
}

sub name { $_[0]->{_name} }
sub table { $_[0]->{_table}->focus }
sub detach { delete $_[0]->{_table} }

sub build { die "You must override build"; }

sub is_built {
    my ($o) = @_;
    for my $k (keys %$o) { return 1 if $k !~ m/^_/; }
    0;
}
# someday distinguish between built, active, and stale
*is_active = \&is_built;

sub drop {
    my ($o) = @_;
    for my $k (keys %$o) {
	next if $k =~ m/^_/;
	delete $o->{$k};
    }
}

sub rebuild {
    my $o = shift;
    $o->drop;
    $o->build(@_);
}

sub peek {
    my ($val, $o, $name) = @_;
    my $built = $val->is_built ? 'ACTIVE' : 'inactive';
    $o->prefix;
    $o->o("$name $built");
    $o->nl;
}

package ObjStore::Table::Index::Field;
use Carp;
use ObjStore;
use base 'ObjStore::Table::Index';

sub new {
    my ($class, $table, $name, $field) = @_;
    $field ||= $name;
    my $o = $class->SUPER::new($table, $name);
    $o->{_field} = $field;
    $o;
}

sub build {
    my ($o, $collision) = @_;
    my $tbl = $o->table;
    my $arr = $tbl->array;
    my $total = $arr->_count();
    my $seg = $o->database_of->create_segment;
    $seg->set_comment($o->name." index");
    my $xx = $o->{ $o->name } = new ObjStore::HV($seg, $total * .25);

    for (my $z=0; $z < $total; $z++) {
	my $rec = $arr->[$z];
	next if !defined $rec;
	my $key = $rec->{$o->{_field}};
	next if !$key;
	my $old = $xx->{ $key };
	if ($old and $collision) {
	    my $do = $collision->($o, $old, $rec);
	    if ($do eq 'neither') {
		delete $rec->{ $key };
		next;
	    } elsif ($do eq 'old') {
		next;
	    } elsif ($do eq 'new') {
	    } else { croak "Collision returned '$do'" }
	}
	$xx->{ $key } = $rec;
    }
}

package ObjStore::Table::Index::GroupBy;
use Carp;
use ObjStore;
use base 'ObjStore::Table::Index';

sub new {
    my ($class, $table, $name, $field) = @_;
    $field ||= $name;
    my $o = $class->SUPER::new($table, $name);
    $o->{_field} = $field;
    $o;
}

sub build {
    my ($o) = @_;
    my $tbl = $o->table();
    my $arr = $tbl->array();
    my $total = $arr->_count();
    my $seg = $o->database_of->create_segment;
    $seg->set_comment($o->name." index");
    my $xx = $o->{ $o->name } = new ObjStore::HV($seg, $total * .1);

    for (my $z=0; $z < $total; $z++) {
	my $rec = $arr->[$z];
	next if !defined $rec;
	my $key = $rec->{$o->{_field}};
	next if !$key;
	my $old = $xx->{ $key } ||= [];
	$old->_Push($rec);
    }
}

package ObjStore::Table::Index::Custom;
#store the perl code in the database?

1;
