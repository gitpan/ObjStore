use strict;

package ObjStore::Table3;
use Carp;
use ObjStore ':ADV';
use base 'ObjStore::HV';
use vars qw($VERSION);
$VERSION = '1.00';

sub new {
    my ($class, $where) = @_;
    croak "$class\->new(where)" if @_ != 2;
    my $o = $class->SUPER::new($where);
    $o;
}

sub index { $_[0]->{$_[1]}; }

sub fetch { 
    my $t=shift;
    my $iname = shift;
    my $i = $t->{ $iname };
    croak "Can't find index '$iname'" if !$i;
    my $c = $i->new_cursor;
    if ($c->seek(@_)) {
	$c->at;
    } else {
	();
    }
}

sub anyx {
    my ($t) = @_;
    $t = $t->table;
    for my $i (values %$t) {
	next unless ref $i && $i->isa('ObjStore::Index');
	return $i if $i->_count;
    }
    undef;
}

sub rows {
    my ($t) = @_;
    my $i = $t->anyx;
    $i? $i->count : 0;
}

sub map {
    my ($t, $sub) = @_;
    my $x = $t->anyx;
    return if !$x;
    $x->map($sub);
}

sub add_index {
    my ($o, $name, $index) = @_;
    if (ref $index eq 'CODE') {
	return $o->{$name} if $o->{$name};
	$index = $index->();
    }
    croak "'$index' doesn't look like an ObjStore::Index" if
	!blessed $index || !$index->isa('ObjStore::Index');
    my $any = $o->anyx;
    if ($any) {
	my $c = $any->new_cursor;
	$c->moveto(-1);
	while (my $v = $c->each(1)) {
	    $index->add($v);
	}
    }
    $o->{ $name } = $index;
}

sub remove_index {
    my ($o, $name) = @_;
    die "$o->remove_index($name): is not an index"
	if !exists $o->{ $name } || !$o->{$name}->isa('ObjStore::Index');
    delete $o->{ $name };
}

sub map_indices {
    my ($o, $c) = @_;
    for my $i (values %$o) {
	next unless ref $i && $i->isa('ObjStore::Index');
	$c->($i);
    }
}

sub CLEAR {
    my ($t) = @_;
    for my $k (keys %$t) { delete $t->{$k} if $t->{$k}->isa('ObjStore::Index'); }
    $t;
}

sub add {
    my ($t, $o) = @_;
    $t->map_indices(sub { shift->add($o) });
    defined wantarray ? $o : ();
}
sub remove {
    my ($t, $o) = @_;
    $t->map_indices(sub { shift->remove($o) });
}

sub compress {
    warn "not yet";
}

sub table { $_[0]; }

package ObjStore::Table3::Database;
use Carp;
use ObjStore;
use base 'ObjStore::Database';
use vars qw'$VERSION @ISA';
push(@ISA, 'ObjStore::Table3');
$VERSION = '1.00';

sub new {
    my $class = shift;
    my $db = $class->SUPER::new(@_);
    $db->table; #force root setup
    $db;
}

sub table {
    my ($db) = @_;
    $db->root('ObjStore::Table3', sub { ObjStore::Table3->new($db) } );
}

sub POSH_ENTER { shift->table; }

1;
__END__

=head1 NAME

  ObjStore::Table3 - RDBMS Style Tables

=head1 SYNOPSIS

  cd table-test ObjStore::Table3::Database

=head1 DESCRIPTION

Unstructured perl databases are probably under-constrained for most
applications.  Tables standardize the interface for storing a bunch of
records and their associated indices.

A table is no more than a collection of indices (as opposed to a some
sort of heavy-weight object).  Think of it like an event manager for
indices.

=head2 API

=over 4

=item * $t->anyx

Returns any non-empty index in the table.

=item * $t->add($e)

Adds $e to all table indices.

=item * $t->remove($e)

Removes $e from all table indices.

=item * $t->index($index_name)

Returns the index named $index_name.

=item * $t->fetch($index_name, @keys)

Returns the record resulting from looking up @keys in the index named
$index_name.

=item * $t->add_index($index)

Adds the index.

=item * $t->remove_index($index)

=item * $t->map_indices($coderef)

Calls $coderef->($index) on each index.

=back

=head2 Representation Independent API

A database can be seen as table, and/or tables can be stored within a
database.  The implementation is only slightly different in either
case.  To smooth things over, an accessor method is provided that
always returns the top-level hash of the table.

=over 4

=item * $t->table

Returns the top-level hash.

=back

=head1 MIGRATION

=head1 BUGS

Usage is a bit more cumbersome than I would like.  The interface will
change slightly as perl supports more overload-type features.

=head1 TODO

=over 4

=item * Expand migration options

=back

=head1 AUTHOR

Copyright © 1997-1998 Joshua Nathaniel Pritikin.  All rights reserved.

This package is free software and is provided "as is" without express
or implied warranty.  It may be used, redistributed and/or modified
under the terms of the Perl Artistic License (see
http://www.perl.com/perl/misc/Artistic.html)

=cut
