use strict;

# DEPRECIATED !!!
package ObjStore::Process;
use Carp;
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
@ISA = qw(ObjStore::HV Exporter);
@EXPORT_OK = qw(txqueue txretry meter checkpoint);  #Loop Exit ?XXX

Carp::cluck("ObjStore::Process is depreciated; see ObjStore::Serve");

$EXE = $0;
$EXE =~ s{^ .* / }{}x;
chop($HOST = `hostname`);

$LoopLevel = 0;
$ExitLevel = 0;
$MAXPENDING = 0;

# Need alternative because realtime updates are not retry'able.
#ObjStore::set_max_retries(0);

# Big program style.
ObjStore::fatal_exceptions(0);

# Don't assume king of the network.
$ObjStore::TRANSACTION_PRIORITY = 0x100;

# Don't wait forever!
for (qw(read write)) { ObjStore::lock_timeout($_,15); }

# Signals will likely happens at strange times.  Be extra careful.
#++$ObjStore::SAFE_EXCEPTIONS;

# Extra debugging.
#Carp->import('verbose');
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
    $$o{chkpt_timer} = 2;  #conf
    $$o{mtime} = time;
    $PROCESS = $o->new_ref('transient','safe');
    $o;
}

sub delay {
    use integer;
    my ($ign, $d) = @_;
    if ($d <120) {"$d secs" }
    elsif ($d < 2*60*60) { $d/60 ." minutes" }
    elsif ($d < 2*60*60*24) { $d/(60**2)." hours" }
    else { $d/(60*60*24)." days" }
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
	    # need better hook? XXX
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
		    if ($ { ref($f) . "::UNLOADED" }) {
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

$TType = 'update';  #default to local, read XXX
sub set_mode {
    my ($o,$m) = @_;
    $TType = $m;
}

sub checkpoint { ++$Checkpoint }

use vars qw($ABORT); # DEPRECIATED
use vars qw($TXOpen @TXtodo @TXready);

# WARNING: please do not call this directly!
sub _checkpoint {
    my ($class, $continue) = @_;
    my $chkpt_timer = 2;
    if ($TXN) {
	my $ok=0;
	# record stats about aborts!
	$TXOpen = 0;
	if (!$ABORT) {
	    $ok = eval {
		if ($PROCESS) {
		    # turn into a method!! XXX
		    # also track server down-time (on restart)
		    if ($PROCESS->deleted()) {
			ObjStore::Process->Exit(0);
			die "another server started up, exiting...";
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
	    undef $TXN;
	}
	$ABORT=0;
	$Elapsed = tv_interval($t1, [gettimeofday]);
    }
    $Checkpoint=0;
    if ($continue) {
	if (!$TXN) {
	    confess "cannot nest dynamic transactions"
		if @ObjStore::TXStack;
	    $TXN = ObjStore::Transaction->new($TType);
	}
	$TXOpen = 1;
	$TxnTime = [gettimeofday];
	Event->timer(-after => $chkpt_timer, -callback => sub { ++$Checkpoint; });
	# don't acquire any unnecessary locks!
    }
}

sub txretry {
    use attrs 'locked';
    lock $TXOpen;
    push @TXready, map { { retry => 1, code => $_ } } @_;
}
sub txqueue {
    use attrs 'locked';
    lock $TXOpen;
    if ($TXOpen) {
	$_->() for @_;
    } else {
	push @TXready, map { { retry => 0, code => $_ } } @_;
    }
}
sub async_checkpoint {
    # avoid regex! XXX
    my ($sleep) = @_;
    while ($ExitLevel >= 1) {
	my $tx;
	do { 
	    lock $TXOpen;
	    $tx = ObjStore::Transaction->new('global', 'read');
	    $TXOpen = 1;
	    push @TXready, @TXtodo;
	    @TXtodo = ();
	};
	sleep $sleep;   #fractional? XXX
	do {
	    lock $TXOpen;
	    $TXOpen=0;
	    !$ABORT? $tx->commit() : $tx->abort();
	    $ABORT=0;
	};
    }
}

sub ondie {
    warn "depreciated";
    push @ONDIE, $_[1];
}

sub meter { ++ $METERS{ $_[$#_] }; }

use vars qw($Init);

sub init_signals {
    $SIG{HUP} = 'IGNORE';
    for my $sig (qw(INT TERM)) {
	$SIG{$sig} = sub { 
	    my $why = "SIG$sig\n";
	    ObjStore::Process->Exit($why);
	};
    }
    $Init = 1;
}

*Loop = \&Loop_single;

sub Loop_mt {
    my ($o) = @_;
    local $Status = 'abnormal';
    local $LoopLevel = $LoopLevel+1;
    ++$ExitLevel;
    if (!$Init) {
	&init_signals;
    }
    while ($ExitLevel >= $LoopLevel) {
	eval {
	    while ($ExitLevel >= $LoopLevel) {
		Event->DoOneEvent();
		next if !lock $TXOpen || !@TXready;
		my @c = @TXready;
		@TXready = ();
		for my $j (@c) {
		    my $c = $$j{code};
		    if ($$j{retry}) { push @TXtodo if !$c->(); }
		    else { $c->(); }
		}
	    }
	};
	if ($@) {
	    ++$ABORT;
	    warn $@;
	}
    }
    $Status
}

sub Loop_single {
    my ($o,$waiter) = @_;
    local $Status = 'abnormal';
    local $LoopLevel = $LoopLevel+1;
    ++$ExitLevel;
#    warn "Loop enter $LoopLevel $ExitLevel";
    &init_signals if !$Init;

    $o->_checkpoint(1) if !$TXN;
    while ($ExitLevel >= $LoopLevel) {
	push @TXready, @TXtodo;
	eval {
	    my @c = @TXready;
	    @TXready = ();
	    for my $j (@c) {
		my $c = $$j{code};
		if ($$j{retry}) { push @TXtodo if !$c->(); }
		else { $c->(); }
	    }
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

# CORE::GLOBAL::exit ?XXX
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

