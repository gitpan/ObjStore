use strict;
package ObjStore::ServerDB;
use Carp;
use ObjStore ':ADV';
require ObjStore::Process;
use base 'ObjStore::HV::Database';
use vars qw($VERSION $AUTOFORK);
$VERSION = '0.02';

sub fork_server {
    my ($o,$path) = @_;
    $path ||= $o->get_pathname() if ref $o;
    my $class = ref $o || $o;
    my $srv = 'osperlserver';
    my $cmd;
    if (grep /blib/, @INC) {
	if (-x "./blib/script/$srv") {
	    # ?XXX never used?
	    $cmd = "$^X -Mblib ./blib/script/$srv -F $path=$class &";
	} else {
	    $cmd = "$srv -Mblib -F $path=$class &";
	}
    } else {
	$cmd = "$srv $path=$class";
    }
#    warn $cmd;
    system $cmd;
}

sub autofork {
    $AUTOFORK = 1;
}

sub new {
    my ($class,$path,$mode,$mask) = @_;

    $mode ||= 'mvcc';
    if ($mode eq 'mvcc' and !-e $path) {
	$class->fork_server($path);
	while (!-e $path) {
	    warn "waiting for $ {path} to exist\n";
	    sleep 1;
	}
    }
    $mask = $mode eq 'update'? 0666 : 0 unless defined $mask;
    my $DB = ObjStore::open($path, $mode, $mask);
    bless $DB, $class if ($class ne 'ObjStore::ServerDB' or
			  blessed $DB eq 'ObjStore::Database');

    if (!defined %Posh::) {
	if ($mode eq 'update') { ### SERVER
	    $DB->subscribe();
	    ObjStore::Process->set_mode('update');
	    
	    begin 'update', sub {
		my $h = $DB->hash;
		#hostile takeover
		my $s = $$h{server} || $DB->create_segment('server');
		$$h{server} = ObjStore::Process->new($s);
	    };
	    die if $@;
	    begin 'update', sub {
		my $top = $DB->hash;
		bless $top, $class.'::Top'
		    if ($class ne 'ObjStore::ServerDB' or 
			blessed $top eq 'ObjStore::HV');
		$top->boot();               #simple is good
		for (values %$top) {
		    # not much point in checking is_evolved...
		    $_->evolve() if blessed $_;
		}
	    };
	    die if $@;
	    begin 'update', sub {
		my $top = $DB->hash;
		for (values %$top) {
		    $_->restart() if blessed $_ && $_->can('restart');
		}
	    };
	    die if $@;
	    
	    # should be READY...
	    ObjStore::Process->autonotify(); #GO

	} else { ### CLIENT
	    begin sub {
		my $top = $DB->hash;
		if ($AUTOFORK and
		    (!$top->{server} or time - $$top{server}{mtime} > 60)) {
		    $DB->fork_server();
		}
	    };
	    die if $@;
	}
    }
    $DB;
}

sub wait_for_commit { shift->hash->{server}->wait_for_commit(); }

package ObjStore::ServerDB::Top;
use ObjStore;
use base 'ObjStore::HV';
use vars qw($VERSION);
$VERSION = '0.02';

use ObjStore::notify qw(new_object);
sub do_new_object {
    no strict 'refs';
    my ($o,$k,$p) = @_;
    unless (defined %{"$p\::"}) {
	my $file = $p;
	$file =~ s,::,/,g;
	require "$file.pm";
    }
    $$o{$k} ||= $p->new($o->create_segment($k));
}

sub boot {}

1;

=head1 NAME

ObjStore::ServerDB - Generic Real-Time Database Server

=head1 SYNOPSIS

    require ObjStore::ServerDB;
    require E::GUI;

    $$o{app} = ObjStore::ServerDB->new('/research/tmp/qsg_gui');
    my $top = $$o{app}->hash;
    $top->new_object('preferences', 'E::GUI');

=head1 DESCRIPTION

Provides a remote method invokation service for persistent objects.

=head1 BOOT METHOD

Normally, you would just call C<$top->new_object(...)> once the
database was open (as above), but sometimes you really need the
database to be created already.  Inherit the class and override the
C<boot> method.

 sub boot {
    my ($o) = @_;
    require E::Icache;
    $$o{icache} ||= E::Icache->new($o->create_segment('icache'));
    require E::Basket;
    $$o{baskets} ||= E::BasketTable->new($o->create_segment('baskets'));
 }

=head1 SEE ALSO

osperlserver, C<ObjStore::Process>, C<ObjStore::notify>

=cut
