use 5.00464; #probably
use strict;
package ObjStore::Serve;
use Carp;
use Exporter ();
use Event; #0.02 or better recommended
use IO::Handle;
use IO::Poll '/POLL/';
use Time::HiRes qw(gettimeofday tv_interval);
use ObjStore;
use base 'ObjStore::HV';
use vars qw(@ISA @EXPORT_OK %EXPORT_TAGS $SERVE %METERS $Init $TXOpen);
push @ISA, 'Exporter', 'osperlserver';
@EXPORT_OK = qw(&txqueue &txretry &meter &exitloop
		$LoopLevel $ExitLevel &init_signals);
# :meld is EXPERIMENTAL!!
%EXPORT_TAGS = (meld => [qw($LoopLevel $ExitLevel &init_signals
			     )]);

sub meter { ++ $METERS{ $_[$#_] }; }
use vars qw(@TXready @TXtodo);
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

sub restart {
    my ($o) = @_;

    $SIG{__WARN__} =
	sub { warn '['.localtime()."] $ObjStore::Server::EXE($$): $_[0]" };
    $SIG{__DIE__} =
	sub { die '['.localtime()."] $ObjStore::Server::EXE($$): $_[0]" };

    # If we made it here, our assumption is that the database
    # is not currently being serviced by a live server.  We
    # will take control.
    $ObjStore::TRANSACTION_PRIORITY = 0x8000;

    $SERVE = $o->new_ref('transient','hard');
    my $h = $$o{history} ||= [];
    my $now = time;
    $h->UNSHIFT({ restart => $now, mtime => $now, recent => [], total => {} });
}

use vars qw($Status $LoopLevel $ExitLevel);

$LoopLevel = $ExitLevel = 0;
ObjStore::set_max_retries(0);
ObjStore::fatal_exceptions(0);

# Don't wait forever! XXX
for (qw(read write)) { ObjStore::lock_timeout($_,15); }

sub init_signals {
    $SIG{HUP} = 'IGNORE';
    for my $sig (qw(INT TERM)) {
        $SIG{$sig} = sub { my $why = "SIG$sig\n"; exitloop($why); };
    }
}

################################################# STATS

use vars qw($BeforeCheckpoint $ChkptTime $TxnTime $Aborts $Commits
	    $LoopTime);
$LoopTime = 2;

sub before_checkpoint {
    my ($t) = @_;
    $TXOpen=0;
    $t ||= ObjStore::Transaction::get_current();
    if ($SERVE and !$t->is_aborted) {
	eval {
	    my $now = [gettimeofday];

	    # make sure we're still in charge
	    ObjStore::Server->touch($$now[0]);

	    # update various stats
	    my $o = $SERVE->focus;
	    my $r = $o->{history}[0];
	    
	    my $recent = $$r{recent};
	    my $prior = $recent->[$#$recent] if @$recent;
	    $prior->{commit_time} = $ChkptTime if $prior;
	    push @$recent, { loop_time=> tv_interval($TxnTime, $now),%METERS };
	    shift @$recent if @$recent > 10;
	    
	    if ($prior) {
		local $^W=0; #lexical warnings XXX
		my $t = $$r{total};
		while (my($k,$v) = each %$prior) { $t->{$k} += $v; }
		if ($Aborts) { $t->{aborts} += $Aborts; $Aborts = 0; }
		if ($Commits) { $t->{commits} += $Commits; $Commits = 0; }
	    }
	    $$r{mtime} = $$now[0];
	    $BeforeCheckpoint = $now;
	    
	    $LoopTime = $$o{looptm} ||= 2;
	    %METERS = ();
	    $t->post_transaction(); #1
	};
	if ($@) { $t->abort; warn; }
    }
    $t->is_aborted? ++$Aborts : ++$Commits;
}

sub after_checkpoint {
    $ChkptTime = tv_interval($BeforeCheckpoint, [gettimeofday]);
}

sub start_transaction {
    $TxnTime = [gettimeofday];
    $TXOpen = 1;
    push @TXready, @TXtodo;
    @TXtodo = ();
}

sub dotodo {
    my @c = @TXready;
    @TXready = ();
    for my $j (@c) {    my $c = $$j{code};
        if ($$j{retry}) { push @TXtodo if !$c->(); }
        else { $c->(); }
    }
}

################################################# default

sub defaultLoop {
    init_autonotify();
    *Loop = \&Loop_single;
    shift->Loop();
}

################################################# without threads
use vars qw($TXN $Checkpoint);

sub Loop_single {
    my ($o,$waiter) = @_;
    local $Status = 'abnormal';
    local $LoopLevel = $LoopLevel+1;
    ++$ExitLevel;
#    warn "Loop enter $LoopLevel $ExitLevel";
    if (!$Init) { &init_signals; ++$Init; }

    $o->_checkpoint(1) if !$TXN;
    while ($ExitLevel >= $LoopLevel) {
        eval {
            dotodo();
            if ($waiter and $waiter->()) {
		exitloop('ok');
            } else {
                while (!$Checkpoint and !$TXN->is_aborted) {Event->DoOneEvent() }
            }
        };
        if ($@) { $TXN->abort; warn }
        $o->_checkpoint($ExitLevel);
    }

#    warn "Loop exit $LoopLevel $ExitLevel = $Status";
    $Status;
}

# WARNING: please do not call this directly!
use vars qw($UseOSChkpt);
sub _checkpoint {
    my ($class, $continue) = @_;
    if ($TXN) {
	before_checkpoint($TXN);
        if (!$TXN->is_aborted and $continue and $UseOSChkpt) {
            # This will not work properly until the bridge code
            # is rewritten. XXX
            $TXN->checkpoint();
        } else {
            $TXN->commit();
            undef $TXN;
        }
        after_checkpoint();
    }
    $Checkpoint=0;
    if ($continue) {
        if (!$TXN) {
            confess "cannot nest dynamic transactions"
                if @ObjStore::Transaction::Stack;
            $TXN = ObjStore::Transaction->new($SERVE? 'update' : 'read');
        }
        start_transaction();
        Event->timer(-after => $LoopTime, -callback => sub {++$Checkpoint});
        # don't acquire any unnecessary locks!
    }
}

################################################# threads (single)

sub Loop_async {
    my ($Q) = @_;
    local $Status = 'abnormal';
    local $LoopLevel = $LoopLevel+1;
    ++$ExitLevel;
    if (!$Init) { &init_signals; ++$Init; }
    while ($ExitLevel >= $LoopLevel) {
	begin 'update', sub {
	    # not thread-safe? XXX
	    Event->timer(-after => $LoopTime, -callback => sub {
			     $Q->enqueue(DATA => 0, PRIORITY => 1)
			 });
            start_transaction();
	    dotodo() if @TXready;
	    while (1) {
		my $do = $Q->dequeue;
		return if !ref $do;  #checkpoint
		$do->();
	    }
	    before_checkpoint();
	};
	warn if $@;
	after_checkpoint();
    }
    $Status
}

################################################# threads (multi)

sub Loop_mt {
    my ($o) = @_;
    local $Status = 'abnormal';
    local $LoopLevel = $LoopLevel+1;
    ++$ExitLevel;
    if (!$Init) { &init_signals; ++$Init; }
    while ($ExitLevel >= $LoopLevel) {
        lock $TXOpen;
        eval {
            dotodo() if @TXready;
            Event->DoOneEvent();
        };
        if ($@) {
            ObjStore::Transction::get_current()->abort();
            warn;
        }
    }
    $Status
}

sub async_checkpoint {
    # regex are not thread-safe! XXX
    while ($ExitLevel >= 1) {
        my $tx;
        do { 
            lock $TXOpen;
	    # think about updates XXX
            $tx = ObjStore::Transaction->new('global', 'read');
            start_transaction();
        };
        sleep $LoopTime;   #fractional? XXX
        do {
            lock $TXOpen;
	    before_checkpoint($tx);
            $tx->commit();
            after_checkpoint();
        };
    }
}

################################################# Exit

sub exitloop {
    my ($o,$st) = @_;
    $st ||= 0;
    --$ExitLevel;
    if ($LoopLevel == 0 or $st eq 'FORCE') {
        exit($st? int $st:0);
    } else {
        $st=0 if !defined $st;
        $Status = $st;
    }
}

################################################# notifications

# separate file?
use vars qw($OVERFLOW);

my $notifyEv;
sub init_autonotify {
    die "autonotify already invoked" if $notifyEv;
    my ($Q) = @_;
    my $fh = IO::Handle->new();
    $fh->fdopen(ObjStore::Notification->_get_fd(), "r");
    my $cb = ($Q? sub { $Q->enqueue(DATA => \&dispatch_notifications,
				    PRIORITY => 2) }
	      : \&dispatch_notifications);
    $notifyEv = Event->io(-handle => $fh, -events => POLLRDNORM,
                          -callback => $cb);
}

#    ObjStore::Notification->set_queue_size(512);

$OVERFLOW=0;
sub dispatch_notifications {
    # split out overflow detect? XXX
    my ($sz, $pend, $over) = ObjStore::Notification->queue_status();
    #       $MAXPENDING = $pend if $pend > $MAXPENDING;
    if ($over != $OVERFLOW) {
	warn "lost ".($over-$OVERFLOW)." messages";
	$OVERFLOW = $over;
    }

    my $max = 10;  # XXX?
    begin 'update', sub { # need transaction? XXX
	while (my $note = ObjStore::Notification->receive(0) and $max--) {
	    my $why = $note->why();
	    my $f = $note->focus();
	    my @args = split /$;/, $why;
	    my $call = shift @args;
	    warn "$f->$call(".join(', ',@args).")\n"
		if $osperlserver::Debug{n};
	    meter(ref($f)."->".$call);
	    my $mname = "do_$call";
	    my $m = $f->can($mname);
	    if (!$m) {
		no strict 'refs';
		if ($ { ref($f) . "::UNLOADED" }) {
		    warn "autonotify: attempt to invoke method '$mname' on unloaded class ".ref $f."\n";
		} else {
		    warn "autonotify: don't know how to $f->$mname(".join(', ',@args).") (ignored)\n";
		    # warn "Loaded: ".join(" ",sort keys %INC)."\n";
		}
		next
	    }
	    $m->($f, @args);
	    # fallback to searching @{ blessed($m)."::NOTIFY" } ??XXX
	}
    };
    warn if $@;
}

1;
__END__

=head1 NAME

    ObjStore::Serve - event loop integration

=head1 SYNOPSIS

=head1 DESCRIPTION

EXPERIMENTAL package to integrate ObjStore transactions with Event.
Implements dynamic transactions.

=head1 SEE ALSO

C<Event>, C<ObjStore>

=cut
