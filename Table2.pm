use strict;

=head1 NAME

  ObjStore::Table2 - Simulated RDBMS Tables

=head1 SYNOPSIS

  # posh 1.21 (Perl 5.00454 ObjectStore Release 5.0.1.0)
  cd table-test ObjStore::Table2::Database

  my $a = $db->array; for (1..10) { $a->_Push({row => $_}) }

  $db->table->new_index('Field', 'row');
  $db->table->build_indices;

=head1 DESCRIPTION

 $at = TABLE ObjStore::Table2 {
  array[10] of ObjStore::HV {
    row => 1,
  },
  indices: ROW;
 },

Unstructured perl databases are probably under-constrained for most
applications.  Tables standardize the interface for storing a bunch of
records and their associated indices.

=head2 Raw Representation

 $at = ObjStore::Table2 {
  _array => ObjStore::AV [
    ObjStore::HV {
      row => 1,
    },
    ObjStore::HV {
      row => 2,
    },
    ObjStore::HV {
      row => 3,
    },
    ...
  ],
  _index_segments => 1,
  row => ObjStore::Table::Index::Field {
    _field => 'row',
    _name => 'row',
    _segment => 6,
    _table => ObjStore::Ref => ObjStore::Table2 ...
    ctime => 882030349,
    map => ObjStore::HV {
      1 => ObjStore::HV ...
      10 => ObjStore::HV ...
      2 => ObjStore::HV ...
      ...
    },
    row => ObjStore::HV ...
  },
 },

=head2 API

=over 4

=cut

# This is the second version of the Table interface.
package ObjStore::Table2;
use Carp;
use ObjStore ':ADV';
use base 'ObjStore::HV';
use vars qw($VERSION);

$VERSION = '1.00';

sub new {
    my ($class, $where, $size) = @_;
    croak "$class\->new(where, size)" if @_ != 3;
    my $o = $class->SUPER::new($where);
    my $seg = $o->database_of->create_segment;
    $seg->set_comment("table $size");
    $o->{_array} = new ObjStore::AV($seg, $size);
    $o->{_index_segments} = 1;
    $o;
}

sub indices { croak "indices method is depreciated in Table2" }

=item * $t->index($index_name)

Returns the index named $index_name.

=cut

sub index { $_[0]->{$_[1]}; }

=item * $t->fetch($index_name, $key)

Returns the record resulting from looking up $key in the index named
$index_name.

=cut

sub fetch { my $o=shift; $o->{ shift() }->fetch(@_) }

=item * $t->index_segments($yes)

Indices can be allocated in their own segments or in the same segment
as the table array.  The default is to use separate segments.

=cut

sub index_segments { $_[0]->{_index_segments} = $_[1] }

=item * $t->new_index($type, @ARGS)

Creates an index of type $type using @ARGS and adds it to the table.

=cut

sub new_index {
    my ($o, $type, @REST) = @_;
    my $class = 'ObjStore::Table::Index::'.$type;  #short-cut
    $o->add_index($class->new($o, @REST));
}

=item * $t->add_index($index)

Adds the given index to the table.

=cut

sub add_index {
    my ($o, $index) = @_;
    $o->{ $index->name } = $index;
}

=item * $t->remove_index($index)

=cut

sub remove_index {
    my ($o, $name) = @_;
    die "$o->remove_index($name): index doesn't exist"
	if !exists $o->{ $name };
    delete $o->{ $name };
}

=item * $t->build_indices

=cut

sub build_indices   { shift->map_indices(sub { shift->build; }); }

=item * $t->rebuild_indices

=cut

sub rebuild_indices { shift->map_indices(sub { shift->rebuild; }); }

=item * $t->drop_indices

=cut

sub drop_indices    { shift->map_indices(sub { shift->drop; }); }

=item * $t->repair_indices($rec, $array_index)

Attempt to repair all indices after a change at $array_index.  $rec
is the record that was added or deleted at $array_index.

=cut

sub repair_indices  { 
    my ($o, $rec, $x) = @_;
    $o->map_indices(sub { shift->repair($rec, $x) })
}

=item * $t->map_indices($coderef)

Invokes $coderef->($index) over each index.

=back

=cut

sub map_indices {
    my ($o, $c) = @_;
    for my $i (values %$o) {
	next unless ref $i && $i->isa('ObjStore::Table::Index');
	$c->($i);
    }
}

=head2 Representation Independent API

A database can essentially be a table or tables can be stored within
a database.  The implementation is only slightly different in either
case.  To smooth things over, a few accessor methods are provided that
always work consistently.

=over 4

=item * $t->table

Returns the top-level hash.

=cut

sub table { $_[0]; }

=item * $t->array

Returns the row array.

=cut

sub array { $_[0]->{_array}; }

=back

=cut

sub POSH_PEEK {
    my ($val, $o, $name) = @_;
    $o->o("TABLE ". $name . " {");
    $o->nl;
    $o->indent(sub {
	my $ar = $val->array;
	$o->o("array[".$ar->_count ."] of ");
	$o->peek_any($ar->[0]);
	$o->nl;
	my $table = $val->table;
	my @index;
	my @other;
	while (my ($k,$v) = each %$table) {
	    if (ref $v and $v->isa('ObjStore::Table::Index')) {
		push(@index, $v);
	    } else {
		push(@other, $k);
	    }
	}
	$o->o("indices: ");
	$o->o(join(', ',sort map { $_->is_built? uc($_->name):$_->name } @index));
	$o->o(";");
	$o->nl;
	for my $k (sort @other) {
	    next if $k =~ m/^_/;
	    $o->o("$k => ");
	    my $v = $table->{$k};
	    $o->peek_any($v);
	    $o->nl;
	}
    });
    $o->o("},");
    $o->nl;
}

sub POSH_CD {
    my ($t, $to) = @_;
    return $t->array if $to eq 'array';
    if ($to =~ m/^\d+$/) {
	$t->array->[$to];
    } else {
	$t->table->{$to};
    }
}

sub BLESS {
    return $_[0]->SUPER::BLESS($_[1]) if ref $_[0];
    my ($class, $o) = @_;
    if ($o->isa('ObjStore::Table')) {
	my $t = $o->table;
	$t->{_array} = $t->{'array'};
	delete $t->{'array'};
	my $ix = $t->{'indices'};
	for my $i (keys %$ix) {
	    $t->{$i} = $ix->{$i};
	}
	delete $t->{'indices'};
    }
    $class->SUPER::BLESS($o);
}

package ObjStore::Table2::Database;
use Carp;
use ObjStore;
use base 'ObjStore::Database';
use vars '@ISA';
push(@ISA, 'ObjStore::Table2');

sub ROOT() { 'table' }
sub default_size() { 21 }  #can override

sub new {
    my $class = shift;
    my $db = $class->SUPER::new(@_);
    $db->table; #setup root
    $db;
}

sub table {
    my ($db) = @_;
    $db->root(&ROOT, sub { ObjStore::Table2->new($db, &default_size) } );
}
sub array { $_[0]->root(&ROOT)->{_array}; }

sub BLESS {
    return $_[0]->SUPER::BLESS($_[1]) if ref $_[0];
    my ($class, $db) = @_;
    if ($db->isa('ObjStore::HV::Database')) {
	warn "Migrating $db to $class...\n";
	my $o = $db->table;
	my $ar = $o->array;
	my $hash = $db->hash;
	for my $z (values %$hash) { $ar->_Push($z); }
	$db->destroy_root($db->ROOT);
    }
    $class->SUPER::BLESS($db);
    bless $db->table, 'ObjStore::Table2';
    $db;
}

sub POSH_ENTER { shift->table; }

=head2 C<ObjStore::Table::Index>

Base class for indices.

=over 4

=cut

# Should be able to build indices all at once or update incrementally.
package ObjStore::Table::Index;
use ObjStore ':ADV';
use base 'ObjStore::HV';
use Carp;

=item * $class->new($table, $name)

Adds an index called $name to the given table.

=cut

# An index should be autonomous and do it's own clustering.
sub new {
    my ($class, $table, $name) = @_;
    confess "$class->new(table, name)" if @_ != 3;
    my $o = $class->SUPER::new($table);
    $o->{_table} = $table->new_ref($o, 'unsafe'); #safe-ify? XXX
    $o->{_name} = $name;
    $o->set_index_segment($table) if !$table->{_index_segments};
    $o;
}

=item * $i->name

Returns the name of the index.

=cut

sub name { $_[0]->{_name} }

=item * $i->table

Returns the table to which the index is attached.

=cut

sub table { $_[0]->{_table}->focus }
sub detach { delete $_[0]->{_table} } #depreciated? XXX

=item * $i->build

=cut

sub build { die "You must override build"; }
sub repair { die "You must override repair"; }

=item * $i->is_built

=cut

sub is_built {
    my ($o) = @_;
    return 1 if exists $o->{'map'};
    for my $k (keys %$o) { return 1 if $k !~ m/^_/; }  #depreciated
    0;
}
# someday distinguish between built, stale, and actively-updated
*is_active = \&is_built;

=item * $i->drop

Frees the index but preserves enough information to rebuild it.

=cut

sub drop {
    my ($o) = @_;
    for my $k (keys %$o) {
	next if $k =~ m/^_/;
	delete $o->{$k};
    }
}

=item * $i->rebuild

=cut

sub rebuild {
    my $o = shift;
    $o->drop;
    $o->build(@_);
}

# re-think, re-write XXX
sub fetch_key {
    my ($o, $at) = @_;
    confess $o if @_ != 2;
#    warn "$at $o->{_field}";
    my @c = split(m/\-\>/, $o->{_field});
    while (@c) {
	confess "fetch_key broken path $o->{_field}" if !$at;
	if (blessed $at && $at->can("FETCH")) {
	    if ($at->isa('ObjStore::AVHV')) {
		$at = $at->{shift @c};
	    } else {
		$at = $at->FETCH(shift @c);
	    }
	} else {
	    my $t = reftype $at;
	    if ($t eq 'HASH') {
		$at = $at->{shift @c};
	    } elsif ($t eq 'ARRAY') {
		$at = $at->[shift @c];
	    } else {
		confess "fetch_key type '$t' unknown ($at: $o->{_field})";
	    }
	}
    }
    $at;
}

sub fetch { 
    my $o = shift; 
    my $map = $o->FETCH('map');
#    confess $o if !$map;
    $map->{ shift() };
}

=item * $i->set_index_segment($segment)

Sets the segment where the index will be created.  May only be called
once.  A different API will be available for multisegment indices.

=cut

sub set_index_segment {
    my ($o, $s) = @_;
    confess "$o->set_index_segment: already set" if exists $o->{_segment};
    $s ||= $o->segment_of;
    $s = $s->segment_of if ref $s;
    $o->{_segment} = ref $s? $s->get_number : $s;
}

sub index_segment {
    my ($o) = @_;
    if (!exists $o->{_segment}) {
	my $s = $o->database_of->create_segment;
	$s->set_comment($o->name." index");
	$o->{_segment} = $s->get_number;
    }
    $o->database_of->get_segment($o->{_segment});
}

=back

=cut

package ObjStore::Table::Index::Field;
use Carp;
use ObjStore;
use base 'ObjStore::Table::Index';

=head2 C<ObjStore::Table::Index::Field>

  $table->new_index('Field', $name, $field)

A basic unique index over all records.  $field is an access path into
the records to be indexed.  For example, if your records looks like
this:

  { f1 => [1,2,3] }

The access path would be C<"f1-E<gt>0"> to index the zeroth element of the
array at hash key f1.

=cut

sub new {
    my ($class, $table, $name, $field) = @_;
    $field ||= $name;
    my $o = $class->SUPER::new($table, $name);
    $o->{_field} = $field;
    $o;
}

sub repair {
    # ignores collisions XXX
    # stop-gap until tied arrays work
    my ($o, $rec, $x) = @_;
    croak "$o->repair: not build" if !$o->is_built;
    my $inarray = $o->table->array->[$x];
    my $add = $inarray == $rec;
    my $key = $o->fetch_key($rec);
    if ($add) {
	$o->{'map'}{ $key } = $rec;
    } else {
	delete $o->{'map'}{ $key };
    }
}

sub _is_corrupted {
    # ignores collisions XXX
    my ($o, $vlev) = @_;
    my $err=0;
    return $err if !exists $o->{'map'};
    my $t = $o->table;
    my $xx = $o->{'map'};
    my $a = $t->array;
    for (my $z=0; $z < $a->_count; $z++) {
	my $rec = $a->[$z];
	next if !defined $rec;
	my $key = $o->fetch_key($rec);
	next if !$key;
	my $old = $xx->{ $key };
	if (!$old || $key ne $o->fetch_key($old)) {
	    $old = 'undef' if !defined $old;
	    warn "$o->is_corrupted: key '$key' != '$old' ($rec)" if $vlev;
	    ++$err;
	}
    }
    $err;
}

sub build {
    use integer;
    my ($o, $collision) = @_;
    warn "$o->build: collision support is experimental" if $collision;
    return if $o->is_built;
    my $t = $o->table;
    my $arr = $t->array;
    my $total = $arr->_count();
    my $xx = $o->{ $o->name } = new ObjStore::HV($o->index_segment,
						 $total * .4 || 50);
    $o->{'map'} = $xx;

    for (my $z=0; $z < $total; $z++) {
	my $rec = $arr->[$z];
	next if !defined $rec;
	my $key = $o->fetch_key($rec);
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
	    } else { croak "$o->build: collision returned '$do'" }
	}
	$xx->{ $key } = $rec;
    }
    $o->{ctime} = time;
}

package ObjStore::Table::Index::GroupBy;
use Carp;
use ObjStore;
use base 'ObjStore::Table::Index';

=head2 C<ObjStore::Table::Index::GroupBy>

  $table->new_index('GroupBy', $name, $field);

Groups all records into arrays indexed by $field.  $field is an access
path into the records to be indexed.

=cut

sub new {
    my ($class, $table, $name, $field) = @_;
    $field ||= $name;
    my $o = $class->SUPER::new($table, $name);
    $o->{_field} = $field;
    $o;
}

sub build {
    use integer;
    my ($o) = @_;
    return if $o->is_built;
    my $tbl = $o->table();
    my $arr = $tbl->array();
    my $total = $arr->_count();
    my $xx = $o->{ $o->name } = new ObjStore::HV($o->index_segment,
						 $total * .2 || 50);
    $o->{'map'} = $xx;

    for (my $z=0; $z < $total; $z++) {
	my $rec = $arr->[$z];
	next if !defined $rec;
	my $key = $o->fetch_key($rec);
	next if !$key;
	my $old = $xx->{ $key } ||= [];
	$old->_Push($rec);
    }
    $o->{ctime} = time;
}

1;

=head1 MIGRATION

Both C<ObjStore::HV::Database> and C<ObjStore::Table> are
bless-migratible to C<ObjStore::Table2>.

The old C<ObjStore::Table> stored all indices in a hash under the
top-level.  Table2 stores them directly in the top-level.  This should
make index lookups slightly more efficient.

=head1 BUGS

Usage is a bit more cumbersome than I would like.  The interface will
change slightly as perl supports more overload-type features.

=head1 TODO

=over 4

=item *

Automatic index maintanance: the array will be overloaded such that
adds/deletes optionally trigger index updates

=item *

More built-in index types

=back

=head1 AUTHOR

Copyright (c) 1997 Joshua Nathaniel Pritikin.  All rights reserved.

This package is free software; you can redistribute it and/or modify
it under the same terms as perl itself.  This software is provided "as
is" without express or implied warranty.

=cut