use strict;
package ObjStore::AVHV::Fields;
use base 'ObjStore::HV';

# '__VERSION__' is appropriate because it might not be a timestamp.

sub is_system_field {  #depreciated?
    my ($o, $name) = @_;
    $name =~ m'^_';
}

sub is_compatible {
    my ($pfields, $fields) = @_;
    my $yes=1;
    for my $k (keys %$fields) {
	next if $pfields->is_system_field($k);
	my $xx = $pfields->{$k} || -1;
	if ($xx != $fields->{$k}) { $yes=0; last }
    }
    $yes;
}

package ObjStore::AVHV;
use Carp;
use base 'ObjStore::AV';

push(@ObjStore::Database::OPEN1, \&verify_class_fields);
sub LAYOUTS { 'layouts' }  #root XXX

sub FETCH_TRANSIENT_LAYOUT {
    my ($class) = @_;
    no strict 'refs';
    croak '\%{'.$class.'\::FIELDS} not found' if !defined %{"$class\::FIELDS"};
    my $fm = \%{"$class\::FIELDS"};
    $fm->{__VERSION__} ||= $ObjStore::COMPILE_TIME;
    $fm;
}

sub fetch_class_fields {
    my ($db, $class) = @_;
    my $priv = $db->_get_private_root;
    my $layouts = ($priv->{&LAYOUTS} ||= ObjStore::HV->new($db, 40));
    my $pfields = ($layouts->{$class} ||=
		   bless { __VERSION__ => 0 }, 'ObjStore::AVHV::Fields');

    my $fields = FETCH_TRANSIENT_LAYOUT($class);
    my $redo = ($pfields->{__CLASS__} or '') ne $class;

    if ($redo or $pfields->{__VERSION__} != $fields->{__VERSION__}) {

	if ($redo or !$pfields->is_compatible($fields)) {
	    $pfields = $layouts->{$class} =
		bless($fields, 'ObjStore::AVHV::Fields');
	    $pfields->{__CLASS__} = $class;
	    $pfields->{__VERSION__} = $fields->{__VERSION__};
	}
    }
    $pfields->const;
    $pfields;
}

# insure(transient __VERSION__ >= persistent __VERSION__)
# (transient side must drive evolution, yes?)
sub verify_class_fields {
    my ($db) = @_;
    return if $] < 5.00450;
    my $priv = $db->_get_private_root;
    return if (!$priv or !exists $priv->{&LAYOUTS});
    my $layouts = $priv->{&LAYOUTS};

    # for all class layouts
    while (my ($class, $pfields) = each %$layouts) {
	croak "Field map for $class is set to $pfields->{__CLASS__}" if
	    $pfields->{__CLASS__} ne $class;
	no strict 'refs';
	next if !defined %{"$class\::FIELDS"};
	my $fields = \%{"$class\::FIELDS"};
	if (!$pfields->is_compatible($fields)) {
	    if ($fields->{__VERSION__} <= $pfields->{__VERSION__}) {
		$fields->{__VERSION__} = $pfields->{__VERSION__}+1;
	    }
	}
    }
}

sub new {
    require 5.00452;
    my ($class, $where, $init) = @_;
    croak "$class->new(where, init)" if @_ < 2;
    my $fmap = fetch_class_fields($where->database_of, $class);
    my $o = $class->SUPER::new($where, $fmap->{__MAX__}+1);
    $o->[0] = $fmap;
    if ($init) {
	while (my ($k,$v) = each %$init) {
	    croak "Bad key '$k' for $fmap" if !exists $fmap->{$k};
	    $o->{$k} = $v;
	}
    }
    $o;
}

sub is_evolved {
    my ($o) = @_;
    my $class = ref $o;
    my $fields = FETCH_TRANSIENT_LAYOUT($class);
    my $pfm = $o->[0];
    ($pfm->{__CLASS__} eq $class &&
     $pfm->{__VERSION__} == $fields->{__VERSION__});
}

sub evolve {
    require 5.00452;
    my ($o) = @_;
    my $class = ref $o;
    my $fields = FETCH_TRANSIENT_LAYOUT($class);
    my $pfields = $o->[0];

    if (! $pfields->is_compatible($fields)) {
	#copy interesting fields to @tmp
	my @tmp;
	while (my ($k,$v) = each %$pfields) {
	    next if $pfields->is_system_field($k);
	    push(@tmp, [$k,$o->[$v]]) if exists $fields->{$k};
	}

	#clear $o
	for (my $x=0; $x < $o->_count; $x++) { $o->[$x] = undef }

	#copy @tmp back using new schema
	for my $z (@tmp) { $o->[$fields->{$z->[0]}] = $z->[1]; }

	$o->[0] = fetch_class_fields($o->database_of, ref $o);
    }
    $fields->{__VERSION__} = $pfields->{__VERSION__};
}

#sub POSH_CD { my ($a, $f) = @_; $a->{$f}; }

# Hash style, but in square brackets
sub POSH_PEEK {
    require 5.00452;
    my ($val, $o, $name) = @_;
    my $fm = $val->[0];
    my @F = sort grep { !$fm->is_system_field($_) } keys(%$fm);
    $o->{coverage} += scalar @F;
    my $big = @F > $o->{width};
    my $limit = $big ? $o->{summary_width}-1 : $#F;
    
    $o->o($name . " [");
    $o->nl;
    $o->indent(sub {
	for my $x (0..$limit) {
	    my $k = $F[$x];
	    my $v = $val->[$fm->{$k}];
	    
	    $o->o("$k => ");
	    $o->peek_any($v);
	    $o->nl;
	}
	if ($big) { $o->o("..."); $o->nl; }
    });
    $o->o("],");
    $o->nl;
}

1;

=head1 NAME

  ObjStore::AVHV - Hash interface, array performance

=head1 SYNOPSIS

  package MatchMaker::Person;
  use base 'ObjStore::AVHV';
  use fields qw/ height hairstyle haircolor shoetype favorites /;

=head1 DESCRIPTION

Support for extremely efficient objects.

=head1 TODO

=over 4

=item * More documentation

=back

=cut
