use strict;

package ObjStore::Process;
use Carp;
Carp->import('verbose');
use Exporter ();
use ObjStore;
use Event; #0.02 or better recommended
use IO::Handle;
use IO::Poll '/POLL/';
use Time::HiRes qw(gettimeofday tv_interval);
use vars (qw($VERSION @ISA @EXPORT_OK),
	  qw($HOST $EXE $PROCESS $AUTONOTE $MAXPENDING %METERS),
	  qw($Status $LoopLevel $ExitLevel),  #loop
	 );
$VERSION = '0.05';
@ISA = qw(ObjStore::HV Event);
@EXPORT_OK = qw(meter checkpoint);  #Loop Exit ?XXX
#
# We actually sub-class Event so other processes could theortically
# send messages that tweaked remote event loops (without additional
# glue code).  Whether this is actually useful remains to be seen.
#
# Perhaps the real benefit is that it sort-of makes sense conceptually.

$EXE = $0;
$EXE =~ s{^ .* / }{}x;
chop($HOST = `hostname`);

$LoopLevel = 0;
$ExitLevel = 0;
$MAXPENDING = 0;

# Need alternative because realtime updates are not retry'able.
ObjStore::set_max_retries(0);

# Big program style.
ObjStore::fatal_exceptions(0);

# Don't assume king of the network.
$ObjStore::TRANSACTION_PRIORITY = 0x100;

# Don't wait forever!
for (qw(read write)) { ObjStore::lock_timeout($_,15); }

# Signals will likely happens at strange times.  Be extra careful.
#++$ObjStore::SAFE_EXCEPTIONS;

# Extra debugging.
#++$ObjStore::REGRESS;

sub new {
    $ObjStore::TRANSACTION_PRIORITY = 0xf000 #kingly
	if $ObjStore::TRANSACTION_PRIORITY == 0x100;

    my $o = shift->SUPER::new(@_);
    $$o{exe} = $EXE;
    $$o{argv} = \@ARGV;
    $$o{host} = $HOST;
    $$o{pid} = $$;
    $$o{uid} = getpwuid($>);
    $$o{chkpt_timer} = 2;
    $$o{mtime} = time;
    $PROCESS = $o->new_ref('transient','safe');
    $o;
}

sub wait_for_commit {
    my ($s) = @_;
    confess "$s->wait_for_commit" if !ref $s;
    my $mtime = $$s{mtime};
    my $sref = $s->new_ref('transient','safe');
    ObjStore::Process->Loop(sub { $sref->deleted or $sref->focus->{mtime} != $mtime });
}

sub autonotify {
    carp "autonotify already invoked", return if $AUTONOTE;
    my $fh = IO::Handle->new();
    $fh->fdopen(ObjStore::Notification->_get_fd(), "r");
#    ObjStore::Notification->set_queue_size(512);
    my $overflow = 0;
    my $dispatcher = sub {
	my ($sz, $pend, $over) = ObjStore::Notification->queue_status();
	$MAXPENDING = $pend if $pend > $MAXPENDING;
	if ($over != $overflow) {
	    warn "lost ".($over-$overflow)." messages";
	    $overflow = $over;
	}
	my $max = 10;  # XXX?
	begin 'update', sub { # ?XXX
	    while (my $note = ObjStore::Notification->receive(0) and $max--) {
		my $why = $note->why();
		my $f = $note->focus();
		my @args = split /$;/, $why;
		my $call = shift @args;
		warn "$f->$call(".join(', ',@args).")\n"
		    if $ObjStore::Notification::DEBUG_RECEIVE;
		++$METERS{ $call };
		my $mname = "do_$call";
		my $m = $f->can($mname);
		if (!$m) {
		    no strict 'refs';
		    if ($ { ref $f . "::UNLOADED" }) {
			warn "autonotify: attempt to invoke method '$mname' on unloaded class ".ref $f."\n";
		    } else {
			warn "autonotify: don't know how to $f->$mname(".join(', ',@args).") (ignored)\n";
			#		    warn "Loaded: ".join(" ",sort keys %INC)."\n";
		    }
		    next
		}
		$m->($f, @args);
		# search @{ blessed($m)."::NOTIFY" } ?XXX
	    }
	};
	warn if $@;
    };
    $AUTONOTE = Event->io(-handle => $fh, -events => POLLRDNORM,
			  -callback => $dispatcher);
}

# depreciated?
sub do_debug {
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

# configure checkpoint policy?

use vars qw($TXN $TxnTime $Checkpoint $Elapsed $TType $UseOSChkpt
	    @ONDIE);

$TType = 'update';  #default to read XXX
sub set_mode {
    my ($o,$m) = @_;
    $TType = $m;
}

# another API for full transaction commit?  do we run out of memory otherwise? XXX
sub checkpoint { ++$Checkpoint }

use vars qw($ABORT); # DEPRECIATED

# WARNING: please do not call this directly!
sub _checkpoint {
    my ($class, $continue) = @_;
    my $chkpt_timer = 2;
    if ($TXN) {
	my $ok=0;
	# record stats about aborts!
	if (!$ABORT) {
	    $ok = eval {
		if ($PROCESS) {
		    if ($PROCESS->deleted()) {
			ObjStore::Process->Exit(0);
			die "another server is starting up, exiting...";
		    } 
		    my $s = $PROCESS->focus();
		    $chkpt_timer = $$s{chkpt_timer} if $$s{chkpt_timer};
		    my $st = $$s{stats} ||= [];
		    $st->[$#$st]{commit} = $Elapsed if @$st && $Elapsed;
		    my $now = [gettimeofday];
		    push @$st, { update => tv_interval($TxnTime, $now),
				 pending => $MAXPENDING,
				 meters => \%METERS };
		    shift @$st if @$st > 10;
		    %METERS = ();
		    $$s{mtime} = $now->[0];
		    #		$s->notify('was_commit'); #???
		}
		$TXN->post_transaction(); #1
		1;
	    };
	    warn if $@;
	}
	my $t1 = [gettimeofday];
	# check $TXN->is_aborted !!
	if ($ok and $continue and $UseOSChkpt) {
	    # This will not work properly until the bridge code
	    # is rewritten. XXX
	    $TXN->checkpoint();
	} else {
	    $ok? $TXN->commit() : $TXN->abort();
	    $TXN->post_transaction(); #2
	    confess "transaction mismatch"
		if pop @ObjStore::TxnStack != $TXN;
	    $TXN->destroy();
	    undef $TXN;
	}
	$ABORT=0;
	$Elapsed = tv_interval($t1, [gettimeofday]);
    }
    $Checkpoint=0;
    if ($continue) {
	if (!$TXN) {
	    confess "cannot nest dynamic transaction" if @ObjStore::TxnStack;
	    $TXN = ObjStore::Transaction::new($TType);
	    push @ObjStore::TxnStack, $TXN;
	}
	$TxnTime = [gettimeofday];
	Event->timer(-after => $chkpt_timer, -callback => sub { ++$Checkpoint; });
	# don't acquire any unnecessary locks!
    }
}

sub ondie { push @ONDIE, $_[1]; }

sub meter { ++ $METERS{ $_[$#_] }; }

use vars qw($SigInit);

sub Loop {
    my ($o,$waiter) = @_;
    local $Status = 'abnormal';
    local $LoopLevel = $LoopLevel+1;
    ++$ExitLevel;
#    warn "Loop enter $LoopLevel $ExitLevel";

    if (!$SigInit) {
	$SIG{HUP} = sub {};
	for my $sig (qw(INT TERM)) {
	    $SIG{$sig} = sub { 
		my $why = "SIG$sig\n";
		ObjStore::Process->Exit($why);
	    };
	}
	$SigInit = 1;
    }

    $o->_checkpoint(1) if !$TXN;
    while ($ExitLevel >= $LoopLevel) {
	eval {
	    if ($waiter and $waiter->()) {
		$o->Exit()
	    } else {
		while (!$Checkpoint and !$ABORT) { Event->DoOneEvent(); }
	    }
	};
	if ($@) {
	    my $ok=0;
	    my $err = $@;
	    while (my $x = shift @ONDIE) {
		my $do = $x->($err);
		if ($do eq 'exit') {
		    $o->Exit(1); ++$ABORT; ++$ok; last;
		} elsif ($do eq 'abort') {
		    ++$ABORT; ++$ok; last;
		}
		# non-abort path?
		# exit toplevel?
	    }
	    @ONDIE=(); #??
	    ++$ABORT, warn $err if !$ok;
	}
	$o->_checkpoint($ExitLevel);
    }

#    warn "Loop exit $LoopLevel $ExitLevel = $Status";
    $Status;
}

sub Exit {
    my ($o,$st) = @_;
    # multiple frames at once? XXX
    --$ExitLevel;
#    warn "Loop exit to $ExitLevel";
    if ($LoopLevel == 0) {
	# this never happens? XXX
	confess "CORE::exit";
	CORE::exit($st? $st:0);
    } else {
	$st=0 if !defined $st;
#	warn "Exit $st";
	$Status = $st;
    }
}

# ExitTop ?XXX

# CORE::GLOBAL::exit XXX
sub exit {
    carp "please use 'Exit' to avoid confusion";
    shift->Exit;
}

# Event autoloader magic seems over aggressive XXX
sub NOREFS {}
sub DESTROY {}

$SIG{__WARN__} = sub { warn '['.localtime()."] $EXE($$): $_[0]" };
$SIG{__DIE__} = sub { die '['.localtime()."] $EXE($$): $_[0]" };

1;

=head1 NAME

    ObjStore::Process - ObjStore event loop integration

=head1 SYNOPSIS

    ObjStore::Process->autonotify();

    # store our process info
    $$app{process} = ObjStore::Process->new($app);

    # mainloop
    ObjStore::Process->Loop();

=head1 DESCRIPTION

Experimental package to integrate ObjStore transactions with Event.
Implements dynamic transactions.

Read the source, Luke!

=head1 AUTONOTIFY

Provides a remote method invokation service for persistent objects.
(I'm still trying to come up with an appropriate buzz phrase.  "Active
Database" will probably have to do, but it would really warm my heart
to hear people discuss the possibilities of an "Open Objects
DataBus". :-)

=head1 DEADLOCK AVOIDANCE STRATEGIES

=head1 TODO

Research unix-style daemonization code
  default stderr/stdout redirect (or Tee) to /usr/tmp

=head1 SEE ALSO

C<Event>, C<ObjStore>

=cut
