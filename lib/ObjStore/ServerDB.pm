use strict;
package ObjStore::ServerDB;
use Carp;
use ObjStore ':ADV';
require ObjStore::Process;
use base 'ObjStore::HV::Database';
use vars qw($VERSION $AUTOFORK);
$VERSION = '0.03';

sub fork_server {
    warn "EXPERIMENTAL";
    my ($o,$path) = @_;
    $path ||= $o->get_pathname() if ref $o;
    my $class = ref $o || $o;
    my $srv = 'osperlserver';
    my $cmd;
    if (grep /blib/, @INC) {
	if (-x "./blib/script/$srv") {
	    # ?XXX never used?
	    $cmd = "$^X -Mblib ./blib/script/$srv -F $path &";
	} else {
	    $cmd = "$srv -Mblib -F $path &";
	}
    } else {
	$cmd = "$srv $path=$class";
    }
#    warn $cmd;
    system $cmd;
}

sub autofork {
    warn "EXPERIMENTAL";
    $AUTOFORK = 1;
}

sub new {
    my ($class,$path,$mode,$mask) = @_;
    $mode ||= 'mvcc';
    $mask = $mode eq 'update'? 0666 : 0 unless defined $mask;

    # catch not found errors? XXX
#    if ($mode eq 'mvcc' and !-e $path) {
#	while (!-e $path) {
#	    warn "please start a server for $path\n";
#	    sleep 1;
#	}
#    }
    my $DB = ObjStore::open($path, $mode, $mask);

    if (!defined %Posh:: and $mode ne 'update') { ### CLIENT
	begin sub {
	    my $top = $DB->hash;
	    if ($AUTOFORK and
		(!$top->{server} or time - $$top{server}{mtime} > 60)) {
		$DB->fork_server();
	    }
	};
	die if $@;
    }
    $DB;
}

sub wait_for_commit { shift->hash->{'ObjStore::Process'}->wait_for_commit(); }

package ObjStore::ServerDB::Top;  #move to a separate file?
use Carp;
use ObjStore;
use base 'ObjStore::HV';
use vars qw($VERSION);
$VERSION = '0.04';

sub DELETE {
    my ($h,$k) = @_;
    if (ref $k) {
	for (keys %$h) { $h->SUPER::DELETE($_) if $h->{$_} == $k; }
    } else {
	$h->SUPER::DELETE($k);
    }
}

sub _install {
    my ($o, $i, $pk) = @_;
    $pk ||= ref $i;
    $$o{ $pk } = $i; #overwrite!
    no strict 'refs';
    for my $u (@{"$pk\::ISA"}) {
	$o->_install($i, $u);
    }
}

use ObjStore::notify qw(boot_class);
sub do_boot_class {
    # flag to override?
    my ($o,$class) = @_;
    return if $o->SUPER::FETCH($class);
    ObjStore::require_isa_tree($class);
    my $i = $class->new($o->create_segment($class));
    $o->_install($i);
}

sub boot {
    my $o = shift;
    for my $p (@_) { $o->do_boot_class($p) }
}

1;

=head1 NAME

ObjStore::ServerDB - Generic Real-Time Database Server Framework

=head1 SYNOPSIS

    osperlserver host:/full/path/to/db+=MyClass

=head1 DESCRIPTION

An active database is an framework for tightly integrated
collaboration.  While implementation abstraction is preserved without
hinderance, objects can easy interact in a variety of ways:

=over 4

=item * ABSTRACTION / COLLABORATION

The hash at the top of the database holds the set of cooperating
objects that implement all database functionality.  This hash is
always accessable via C<$any->database_of->hash>.  Furthermore, keys
are populated such that they reflect the C<@ISA> tree of object
instances.

=item * CLIENT / SERVER

Other processes can read the database asyncronously with MVCC
transactions invoke remote method invokations (RMIs) on individual
objects.  See C<ObjStore::notify>.

=item * EVENT MANAGEMENT

The C<Event> API is fully integrated (see C<ObjStore::Process>).
Moreover, low priority jobs can be (persistently) queued for
processing with a variety of scheduling options (see
C<ObjStore::Job>).

=back

=head1 BOOTSTRAPPING

The C<$db->hash->do_boot_class> method creates arbitrary classes and
populates the top-level hash.  There are quite a few ways to invoke
it:

=over 4

=item * COMMAND-LINE

  osperlserver host:/full/path/to/db+=MyClass

=item * RMI

  $db->hash->boot_class('MyClass');

=item * INHERITANCE

  package MyDB::Top;
  require 'ObjStore::ServerDB';
  use base 'ObjStore::ServerDB::Top';
  sub boot {
     my ($o) = @_;
     $o->boot_class('MyClass');
  }

  osperlserver host:/full/path/to/db=MyDB

=back

=cut
