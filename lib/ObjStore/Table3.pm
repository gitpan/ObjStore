use strict;

package ObjStore::Table3;
use Carp;
use ObjStore ':ADV';
#require ObjStore::AV::Set; #?
use base 'ObjStore::HV';
use vars qw($VERSION);
$VERSION = '1.04';

sub new {
    use attrs 'method';
    my ($class, $where) = @_;
    croak "$class\->new(where)" if @_ != 2;
    my $o = $class->SUPER::new($where);
    $o;
}

sub add_index {
    use attrs 'method';
    my ($o, $name, $index) = @_;
    croak "keys starting with underscore are reserved"
	if $name =~ m/^_/;
    if (ref $index eq 'CODE') {
	return $o->{$name} if $o->{$name};
	$index = $index->();
    }
    croak "'$index' doesn't look like a real index" if !blessed $index;

    my $any = $o->anyx;
    if ($any) {
	# index must work like an array ref
	for (my $x=0; $x < $any->FETCHSIZE(); $x++) {
	    $index->add($any->[$x]);
	}
    }
    $o->{ $name } = $index;

    $$o{_primary} ||= $index;
    $$o{_allindices} ||= [];
    $$o{_allindices}->PUSH($name);
}

sub remove_index {
    use attrs 'method';
    my ($o, $name) = @_;
    die "$o->remove_index($name): is not an index"
	if !exists $o->{ $name };
    delete $o->{ $name };
    @{$$o{_allindices}} = grep($_ ne $name, @{$$o{_allindices}});
    if (@{$$o{_allindices}}) {
	$$o{_primary} = $o->index($$o{_allindices}->[0]);
    } else {
	$$o{_primary} = undef;
    }
}

sub index {
    use attrs 'method';
    $_[0]->{$_[1]};
}

sub fetch {
    use attrs 'method';
    my $t=shift;
    my $iname = shift;
    my $i = $t->{ $iname };
    croak "can't find index '$iname'" if !$i;
    my $c = $i->new_cursor;
    if (!wantarray) {
	return $c->seek(@_)? $c->at : undef;
    } else {
	my $pe = ObjStore::PathExam->new;
	$pe->load_args(@_);
	return if !$c->seek($pe);
	my @got;
	while (my $e = $c->at) {
	    last if $pe->compare($e) != 0;
	    push @got, $e;
	    $c->step(1);
	}
	@got;
    }
}

sub primary {
    carp "primary is depreciated";
    my ($o) = @_;
    return if !$$o{_primary};
    $o->index($$o{_primary});
}

sub anyx {
    use attrs 'method';
    my ($o) = @_;
    if ($$o{_primary}) {
	return $$o{_primary};
    } else {
	if ($$o{_allindices}) {
	    for my $i (@{$$o{_allindices}}) {
		return $i if @$i;
	    }
	} else {
	    # bend over backwards...!
	    for my $i (values %$o) {
		next unless blessed $i && $i->isa('ObjStore::Index');
		return $i if @$i;
	    }
	}
    }
    undef;
}

sub rows {
    use attrs 'method';
    my ($t) = @_;
    my $i = $t->anyx;
    $i? $i->count : 0;
}

sub map {
    use attrs 'method';
    my ($t, $sub) = @_;
    my $x = $t->anyx;
    return if !$x;
    $x->map($sub);
}

sub map_indices {
    use attrs 'method';
    my ($o, $c) = @_;
    for my $i (@{$$o{_allindices}}) {
	$c->( $$o{$i} );
    }
}

sub add {
    use attrs 'method';
    my ($t, $o) = @_;
    $t->map_indices(sub { shift->add($o) });
    defined wantarray ? $o : ();
}
sub remove {
    use attrs 'method';
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
    warn "ObjStore::Table3::Database is depreciated; just use ObjStore::HV::Database";
    my $class = shift;
    my $db = $class->SUPER::new(@_);
    begin 'update', sub {
	$db->table; #force root setup
    };
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

Be aware that index cursors may only be used by one thread at a time.
Therefore, it is not particularly useful to store pre-created cursors
in a database.  It's probably faster just to create them transiently
when needed.

=head2 API

=over 4

=item * $t->primary()

Returns the primary index.

=item * $t->anyx

Returns a non-empty index.

=item * $t->add($e)

Adds $e to all table indices.

=item * $t->remove($e)

Removes $e from all table indices.

=item * $t->index($index_name)

Returns the index named $index_name.

=item * $t->fetch($index_name, @keys)

Returns the record resulting from looking up @keys in the index named
$index_name.

=item * $t->add_index($name, $index)

Adds an index.  The index can be a closure if your not sure if it
already exists.

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

Expand migration options?

=head1 TODO

=over 4

=item * INTERFACE

The interface will evolve as perl supports more overload-type
features.

=back

=head1 AUTHOR

Copyright © 1997-1998 Joshua Nathaniel Pritikin.  All rights reserved.

This package is free software and is provided "as is" without express
or implied warranty.  It may be used, redistributed and/or modified
under the terms of the Perl Artistic License (see
http://www.perl.com/perl/misc/Artistic.html)

=cut
