use strict;

package ObjStore::Process;
use Carp;
Carp->import('verbose');
use ObjStore;
use Event; #0.02+ recommended
use IO 1.18;  #1.19+ recommended
use IO::Handle;
use IO::Poll '/POLL/';
use Time::HiRes qw(gettimeofday tv_interval); #should be optional XXX
use vars (qw(@ISA $VERSION),
	  qw($HOST $EXE $PROCESS $NOTER),
	  qw($Status $LoopLevel $ExitLevel),  #loop
	 );
$VERSION = '0.02';
@ISA = qw(ObjStore::HV Event);
#
# We actually _sub-class_ Event so other processes could theortically
# send messages that tweaked remote event loops (without additional
# glue code).  Whether this is actually useful remains to be seen.
#
# Perhaps the real benefit is that it sort-of makes sense conceptually.

$EXE = $0;
$EXE =~ s{^ .* / }{}x;
chop($HOST = `hostname`);

$LoopLevel = 0;
$ExitLevel = 0;

# Need alternative because realtime updates are not retry'able.
ObjStore::set_max_retries(0);

# Big program style.
ObjStore::fatal_exceptions(0);

# Don't assume king of the network.
ObjStore::set_transaction_priority(0x100);

# Extra debugging.
#++$ObjStore::REGRESS;

sub new {
    my $o = shift->SUPER::new(@_);
    $$o{exe} = $EXE;
    $$o{host} = $HOST;
    $$o{pid} = $$;
    $$o{uid} = getpwuid($>);
    $$o{mtime} = time;
    # VERSION hash & overload compare XXX

    $PROCESS = $o->new_ref('transient','hard'); #safe XXX
    ObjStore::set_transaction_priority(0xf000); #kingly
    $o;
}

sub autonotify {
    carp "autonotify already invoked", return if $NOTER;
    my $fh = IO::Handle->new();
    $fh->fdopen(ObjStore::Notification->_get_fd(), "r");
    $NOTER = shift->io(-handle => $fh, -events => POLLRDNORM,
		       -callback => sub { ObjStore::Notification->Receive });
}

sub debug {
    my ($o,$what) = @_;
    if ($what =~ m/^\s+$/) {
	$ObjStore::Notification::DEBUG_RECEIVE = 0;
	warn "debugging off\n";
    } else {
	for (split(/,\s/, $what)) {
	    if ($_ eq 'note') {
		$ObjStore::Notification::DEBUG_RECEIVE = 1
	    } else {
		warn "debug $_ ??";
	    }
	}
    }
}

use vars qw($TXN $ABORT $TxnTime $Checkpoint $Elapsed);

sub checkpoint {
    if ($TXN) {
	my $ok=0;
	$ok = eval {
	    if ($PROCESS) {
		# keep a rolling history! XXX
		my $s = $PROCESS->focus();
		$$s{mtime} = $TxnTime->[0];
		#		$$s{updates} = $rtupdates;
		$$s{update} = tv_interval($TxnTime, [gettimeofday]);
		$$s{commit} = $Elapsed if $Elapsed;
	    }
	    $TXN->post_transaction(); #1
	    1;
	};
	warn if $@;
	my $t1 = [gettimeofday];
	($ok and !$ABORT)? $TXN->commit() : $TXN->abort();
	$ABORT=0;
	$TXN->post_transaction(); #2
	if (pop @ObjStore::TxnStack != $TXN) { confess "transaction mismatch" }
	$TXN->destroy();
	undef $TXN;
	$Elapsed = tv_interval($t1, [gettimeofday]);
    }
    $Checkpoint=0;
    confess "cannot nest dynamic transaction" if @ObjStore::TxnStack;
    $TXN = ObjStore::Transaction::new('update');
    push @ObjStore::TxnStack, $TXN;
    # configure checkpoint policy? XXX
    Event->timer(-after => 2, -callback => sub { ++$Checkpoint; });
    $TxnTime = [gettimeofday];
}

sub Loop {
    local $LoopLevel += 1;
    ++$ExitLevel;

    checkpoint() if !$TXN;
    while ($ExitLevel >= $LoopLevel) {
	eval {
	    while (!$Checkpoint and !$ABORT) { Event->DoOneEvent(); }
	};
	++$ABORT, warn if $@;  #maybe don't warn? XXX
	checkpoint();
    }

    my $st = $Status;
    undef $Status;
    $st;
}

sub Exit {
    my ($o,$st) = @_;
    # multiple frames at once? XXX
    --$ExitLevel;
    if ($LoopLevel == 0) {
#	warn "CORE::exit";
	CORE::exit($st? $st:0);
    } else {
	$st=0 if !defined $st;
#	warn "Exit $st";
	$Status = $st;
    }
}

# CORE::GLOBAL::exit XXX
sub exit {
    carp "please use 'Exit' to avoid confusion";
    shift->Exit;
}

# Event autoloader magic seems over aggressive XXX
sub NOREFS {}
sub DESTROY {}

END{ warn localtime().": $EXE($$) exiting...\n"; } #optional? generic? XXX

#------------------------------------------------ ping protocol --

sub ping {
    my ($o, $timeout) = @_;
    return if time - ($$o{mtime} || 0) > 90;
    $o->notify("pong $$o{pid}\@$$o{host}", "now");
    # (can't notify via 'ping' because WE are ping!)

    my $timer = $o->timer(-after => $timeout,
			  -callback => sub { $o->Exit(0) });
    my $ok = $o->Loop();
#    warn $ok;
    $timer->cancel;
    $ok;
}

sub pong {
    my ($o,$who) = @_;
    my ($pid,$host) = split(/\@/, $who);
    $o->notify("ok") if $pid == $$ && $host eq $HOST;
}

sub ok {
    my ($o) = @_;
    return if $$o{pid} == $$ and $$o{host} eq $HOST; #I AM HAPPY
#    warn "$0 is already running ($$o{uid}:$$o{pid}\@$$o{host})\n";
    $o->Exit(1);
}

1;

=head1 NAME

    ObjStore::Process - ObjStore event loop integration

=head1 SYNOPSIS

    # $app is a persistent hash of application info

    ObjStore::Process->autonotify();

    # exit if a server is already running
    my $p = $$app{process};
    ObjStore::Process->Exit if $p && $p->ping(1);

    # store our process info
    $$app{process} = ObjStore::Process->new($app);

    # mainloop
    ObjStore::Process->Loop();

=head1 DESCRIPTION

Implements dynamic transactions around an event loop.  The Event
module is required.

=head1 AUTONOTIFY

Enables automatic dispatch of notifications.  I'm still trying to come
up with an appropriate buzz phrase for this.  "Active Database" sounds
pretty slick, but it would really warm my heart to hear people discuss
the possibilities of an "Open Objects DataBus" as I walk by in the
hallway.

=head1 DEADLOCK AVOIDANCE STRATEGIES

Each database is open for update in only one process.  All writes are
directed via notifications to this database server process.

Any others?

=head1 PING PROTOCOL

=head1 TODO

Research unix-style daemonization code
  default stderr/stdout redirect (or Tee) to /usr/tmp

documentation

=cut
