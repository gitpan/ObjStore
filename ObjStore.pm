# Copyright (c) 1997 Joshua Nathaniel Pritikin.  All rights reserved.
# This package is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.
package ObjStore;
use strict;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);

$VERSION = 1.05;

=head1 NAME

ObjStore - Perl extension for ObjectStore ODMS

=head1 SYNOPSIS

  use ObjStore;

  $osdir = ObjStore->schema_dir;
  my $DB = ObjStore::Database->open($osdir . "/perltest.db", 0, 0666);

  try_update {
      $top = $DB->root('megabase', $DB->newHV('dict'));
      for (my $x=1; $x < 1000000000; $x++) {
	  $top->{$x} = {
	      id => $x,
	      m1 => "I will not talk in ObjectStore/Perl class.",
	      m2 => "I will read the documentation.",
	  };
      }
  };
  print "[Abort] $@\n" if $@;

=head1 DESCRIPTION

[Run peek on one of our databases so people understand the simplicity
that comes from not having a rigid schema.]

=head1 OBJECTSTORE PHILOSOPHY

ObjectStore is outrageously powerful and sophisticated.  It actually
does way too much for the average get-the-job-done programmer.  The
theme of this interface to ObjectStore is simplicity and easy of use.
The performance of raw ObjectStore is so good that even with a gunky
perl layer, benchmarks will find relational databases left on the
bookshelf.

Specifically, the interface is optimized for flexibility, then memory
performance, then speed.  If you really want speed, wait till Perl5
gets access to pthreads.  Or see the TODO list about dynamic linking
additional C++ objects.

=head1 TRANSACTIONS

1. You cannot access persistent data outside of a transaction.  Care
must be taken that all persistent variables go out of scope before
transactions complete.

    {
	my $var;
	try_update {
	    $var = $DB->root('top');
	};
    }      # $var destroy causes ObjStore exception

2. It is impractical to use 'read' transactions because
collections include embedded cursors.  You cannot be able to iterate
over collections without modifying the cursors in the database.  This
should be construed as a bug in perl.  As a work around, read
transactions are implemented with the abort_only transaction mode.
This mode allows you to modify the database but will not commit the
changes.

=head1 REFERENCE COUNTING

It is not practical to simply make perl types persistent.  Values in
the database have different requirements than transient values and
require a custom solution.

1. All data allocated in the database is reference counted separately
from transient data.

2. You cannot take a reference to a scalar value.

=head1 CONTAINERS

There are a few considerations when creating a container: which
segment, which symantics, and which representation.

=head2 HASHES

    $DB->newHV('array');
    $DB->newHV('dict');

    my $seg = $DB->create_segment;
    $seg->newHV('array');
    $seg->newHV('dict');

Array representations have one caveat:  if they need to resize, any
transient references you might have will become pointers to random
memory.  This case actually doesn''t come up very often.  To mess
up, you need to go through these contortions:

    my $top = $DB->newTiedHV('array');
    my $dict = $top->{dict} = $DB->newHV('dict');
    for (1..14) { $top->{$_} = $_; }   # cause resize of $top

    $dict->{foo} = 'bar';              # $dict points to random OOPS!

    $dict = $top->{dict};              # now $dict OK
    $dict->{foo} = 'bar';              # OK

=head2 SACKS

    $DB->newSack('array');

Sacks are sequential access containers.  They support the following 
methods:

    void $sack->a($element);
    void $sack->r($element);
    int  $sack->contains($element);
    SV*  $sack->first();
    SV*  $sack->next();
    void $sack->bless('classname');

Not very feature-ful, are they?  You''d think you would get a big
efficiency win!  In fact, they are only a little better than
hashes.  Sacks are really just a stop-gap until Larry and friends
figure out how to do tied arrays.

=head1 AUTHOR

Joshua Pritikin, pritikin@mindspring.com

=head1 SEE ALSO

ObjectStore Documentation

=cut

use Carp;
use Config;
use UNIVERSAL qw(isa);

require Exporter;
@ISA         = qw(Exporter);
@EXPORT      = qw(&try_update &try_read);
@EXPORT_OK   = qw(&peek &PoweredByOS);
%EXPORT_TAGS = (ALL =>
		[qw(try_update try_read peek PoweredByOS)]);

bootstrap ObjStore;

sub PoweredByOS { "$Config{sitelib}/PoweredByOS.gif"; }

# try_update { complex transaction }
# print "[Abort] $@\n" if $@;

sub try_update(&) {
    my ($fun) = @_;
    ObjStore->begin_update();
    eval {
#	local $SIG{'__DIE__'};
	&$fun;
    };
    if ($@) {
	ObjStore->abort;
    } else {
	ObjStore->commit;
    }
}

sub try_read(&) {
    my ($fun) = @_;
    ObjStore->begin_abort;
    eval {
#	local $SIG{'__DIE__'};
	&$fun;
    };
    ObjStore->abort;
}

sub peek {
    croak "peek([lv,] value)" if @_ > 2;
    my ($lv, $h);
    if (@_ == 1) {
	$lv=0; $h = shift;
    } else {
	($lv, $h) = @_;
    }
    if (!ref $h) {
	print ' 'x$lv . "$h\n";
	return;
    }
    my $class = ref $h;
    if ($class eq 'HASH') {
	my @S;
	my $x=0;
	while (my($k,$v) = each %$h) {
	    last if $x++ > 21;
	    push(@S, [$k,$v]);
	}
	@S = sort { $a->[0] cmp $b->[0] } @S;
	my $limit = (@S > 20) ? 2 : $#S;
	for $x (0..$limit) {
	    my ($k,$v) = @{$S[$x]};

	    if (ref $v) {
		print ' 'x$lv . "$k => {\n";
		peek($lv+1, $v);
		print ' 'x$lv . "},\n";
	    } else {
		$v = 'undef' if !defined $v;
		print ' 'x$lv . "$k => '$v'\n";
	    }
	}
    } elsif (isa($class, 'ObjStore::CV')) {
	my @S;
	my $x=0;
	for (my $v=$h->first; $v; $v=$h->next) {
	    last if $x++ > 21;
	    push(@S, $v);
	}
	my $limit = (@S > 20) ? 2 : @S;
	for (my $v=$h->first; $v; $v=$h->next) {
	    last if $limit-- <= 0;

	    if (ref $v) {
		print ' 'x$lv . "{\n";
		peek($lv+1, $v);
		print ' 'x$lv . "},\n";
	    } else {
		$v = 'undef' if !defined $v;
		print ' 'x$lv . "'$v'\n";
	    }
	}
    } else {
	die "Unknown class '$class'";
    }
}

package ObjStore::Database;

sub root {
    my ($o, $roottag, $nval) = @_;
    my $root = $o->find_root($roottag);
    $root = $o->create_root($roottag) unless $root;
    $root->set_value($nval) if $nval;
    $root->get_value();
}

sub destroy_root {
    my ($o, $tag) = @_;
    my $root = $o->find_root($tag);
    $root->destroy if $root
}

sub newTiedHV {  #factor
    my ($db, $rep) = @_;
    my $hvobj = $db->newHV($rep);
    my %h;
    tie %h, 'ObjStore::HV', $hvobj;
    \%h;
}

package ObjStore::Segment;

sub newTiedHV {
    my ($seg, $rep) = @_;
    my $hvobj = $seg->newHV($rep);
    my %h;
    tie %h, 'ObjStore::HV', $hvobj;
    \%h;
}

package ObjStore::HV;
use Carp;

sub TIEHASH {
    my ($class, $o) = @_;
    croak "Expecting ObjStore::HV" if ref $o ne 'ObjStore::HV';
    bless $o, $class;
}

sub STORE {
    my ($o, $k, $nval) = @_;
    if (!ref $nval) {
	$o->_STORE($k, $nval);
    } elsif (ref $nval eq 'HASH') {
	if (tied %$nval) {
	    $o->_STORE($k, tied %$nval);
	} else {
	    my $seg = ObjStore::Segment->of($o);
	    my $hv = $seg->newHV('array');         # allow customization XXX
	    while (my($hk,$v) = each %$nval) {
		$hv->STORE($hk, $v);
	    }
	    $o->_STORE($k, $hv);
	}
    } elsif (ref($nval) =~ /^ObjStore\:/) {
	$o->_STORE($k, $nval);
    } else {
	croak "Don't know how to store $nval";
    }
}

sub bless {
    my ($o, $class) = @_;
    $o->set_classname($class);
    my %h;
    tie %h, $class, $o;
    my $h = \%h;
    CORE::bless($h, $class);
}

package ObjStore::CV;
use UNIVERSAL qw(isa);
use Carp;

sub bless {
    my ($o, $class) = @_;
    isa($class, 'ObjStore::CV') or croak "$class is not an ObjStore::CV";
    $o->set_classname($class);
    CORE::bless($o, $class);
}

sub contains {
    my ($o, $e) = @_;
    for (my $x=$o->first; $x; $x=$o->next) {
	return 1 if $e eq $x;
    }
    0;
}

1;
