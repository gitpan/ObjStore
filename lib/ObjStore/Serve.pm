use 5.00464; #probably
use strict;
package ObjStore::Serve;
use Carp;
use Exporter ();
use Event; #0.03 or better recommended
use IO::Handle;
use IO::Poll '/POLL/';
use Time::HiRes qw(gettimeofday tv_interval);
use ObjStore;
use base 'ObjStore::HV';
use vars qw(@ISA @EXPORT_OK %EXPORT_TAGS $SERVE %METERS $Init $TXOpen $VERSION);
$VERSION = '0.03';
push @ISA, 'Exporter', 'osperlserver';
@EXPORT_OK = qw(&txqueue &txretry &meter &exitloop &seconds_delta
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

sub seconds_delta {
    my ($d) = @_;
    if ($d <120) {
	if ($d != int $d) {
	    sprintf "%.2f secs", $d
	} else {
	    "$d sec" . ($d > 1?'s':'')
	}
    }
    elsif ($d < 2*60*60) { int($d/60) ." minutes" }
    elsif ($d < 2*60*60*24) { int($d/(60**2))." hours" }
    else { int($d/(60*60*24))." days" }
}

sub get_all_versions {
    # adapted from Devel::Symdump!
    my ($V, @todo) = @_;
    my @more;
    for my $pack (@todo) {
	no strict;
	while (my ($key,$val) = each %{*{"$pack\::"}}) {
	    local(*ENTRY) = $val;
	    if (defined $val and defined *ENTRY{HASH} and $key =~ /::$/ and 
		$key ne "main::") {

		my($p) = $pack ne "main" ? "$pack\::" : "";
		($p .= $key) =~ s/::$//;
		my $ver = $ {"$p\::VERSION"} if defined $ {"$p\::VERSION"};
		$V->{$p} = $ver if $ver;
		push @more, $p;
	    }
	}
    }
    get_all_versions($V, @more) if @more;
    $V;
}

sub restart {
    my ($o) = @_;

    $SIG{__WARN__} =
	sub { warn '['.localtime()."] $ObjStore::Server::EXE($$): $_[0]" };
    $SIG{__DIE__} =
	sub { die '['.localtime()."] $ObjStore::Server::EXE($$): $_[0]" };

    # If we made it here, our assumption is that the database
    # is not currently being serviced by a live server.
    # We take control.
    $ObjStore::TRANSACTION_PRIORITY = 0x8000;

    $SERVE = $o->new_ref('transient','hard');
    my $h = $$o{history} ||= [];
    my $now = time;
    my $V = get_all_versions({},'main');
    $V->{'perl'} = $];
    $h->UNSHIFT({ VERSION => $V, restart => $now, mtime => $now,
		  recent => [], total => {} });
}

sub VERSION {
    my ($o,$p,$req) = @_;
    return $o->SUPER::VERSION($p) if $p =~ /^[\d\._]$/;
    my $v = $o->{history}[0]{VERSION}{$p} || 0;
    if (defined $req and $req > $v) {
	croak "$p version $req required--this is only version $v"
    } else { $v }
}

use vars qw($Status $LoopLevel $ExitLevel);
$LoopLevel = $ExitLevel = 0;
ObjStore::fatal_exceptions(0);

# Don't wait forever! XXX
for (qw(read write)) { ObjStore::lock_timeout($_,15); }

sub init_signals {
    for my $sig (qw(INT TERM)) {
        $SIG{$sig} = sub { my $why = "SIG$sig\n"; exitloop($why); };
    }
}

################################################# STATS

use vars qw($Aborts $Commits $LoopTime @Commit);
$LoopTime = 2;

my $LoopState;

sub before_checkpoint {
    my ($t) = @_;
    confess $LoopState if $LoopState ne 'start';
    $LoopState = 'before';

    $TXOpen=0;
    $t ||= ObjStore::Transaction::get_current();
    if ($SERVE and !$t->is_aborted) {
	eval {
	    my $now = time;

	    # make sure we're still in charge
	    ObjStore::Server->touch($now);

	    # update various stats
	    my $o = $SERVE->focus;

	    for (@Commit) { $_->($o, $now) }

	    my $r = $o->{history}[0];
	    my $recent = $$r{recent};
	    push @$recent, \%METERS;
	    shift @$recent if @$recent > 10;

	    do {
		local $^W=0; #lexical warnings XXX
		my $tot = $$r{total};
		while (my($k,$v) = each %METERS) { $tot->{$k} += $v; }
		if ($Aborts) { $tot->{aborts} += $Aborts; $Aborts = 0; }
		if ($Commits) { $tot->{commits} += $Commits; $Commits = 0; }
	    };
	    $$r{mtime} = $now;
	    
	    $LoopTime = $$o{looptm} ||= 2;
	    %METERS = ();
	    $t->post_transaction(); #1
	};
	if ($@) { $t->abort; warn; }
    }
    $t->is_aborted? ++$Aborts : ++$Commits;
}

sub after_checkpoint {
    confess $LoopState if $LoopState ne 'before';
    $LoopState = 'after';
}

sub start_transaction {
    $LoopState ||= 'after';
    confess $LoopState if $LoopState ne 'after';
    $LoopState = 'start';

    $TXOpen = 1;
    push @TXready, @TXtodo;
    @TXtodo = ();
}

use vars qw($TXN $UseOSChkpt);
sub dotodo {
    confess "no transaction" if !lock $TXOpen;
    my @c = @TXready;
    @TXready = ();
    while (@c) {
	my $j = shift @c;
	eval {
	    my $c = $$j{code};
	    if ($$j{retry}) { push @TXtodo, $j if !$c->(); }
	    else { $c->(); }
	};
	if ($@) { $TXN->abort; warn }  # is this correct? XXX
    }
    unshift @TXtodo, @c;
}

sub checkpoint {
    my ($continue) = @_;
    $continue = 1 if !defined $continue;
    if ($TXN) {
	before_checkpoint($TXN);
        if (!$TXN->is_aborted and $continue and $UseOSChkpt) {
            # This will not work properly until Object Design
	    # fixes the checkpoint code. XXX
            $TXN->checkpoint();
        } else {
            $TXN->commit();
            undef $TXN;
        }
        after_checkpoint();
    }
    if ($continue) {
        if (!$TXN) {
            confess "cannot nest dynamic transactions"
                if @ObjStore::Transaction::Stack;
            $TXN = ObjStore::Transaction->new($SERVE? 'update' : 'read');
        }
        start_transaction();
    }
    dotodo();
}

################################################# default
use vars qw($Chkpt);

sub defaultLoop {
    Event->VERSION(0.11);
    require ObjStore::Serve::Notify;
    ObjStore::Serve::Notify::init_autonotify();
    if (!$Init) { &init_signals; ++$Init; }
    checkpoint(1);
    $Chkpt = Event->timer(desc => "ObjStore::Serve checkpoint", priority => -1,
			  interval => \$LoopTime, callback => \&checkpoint);
    Event->add_hooks(asynccheck => sub {
			 $Chkpt->now() if ObjStore::Transaction::is_aborted($TXN)
		     });
    $Event::DIED = sub {
	my ($e,$err) = @_;
	$TXN->abort;
	warn "Event '$e->{desc}' died: $err";
	$Chkpt->now();
    };
    Event::Loop::Loop();
}

################################################# old

sub oldLoop {
    warn "exitloop is broken for oldLoop; sorry";
    require ObjStore::Serve::Notify;
    ObjStore::Serve::Notify::init_autonotify();
    *Loop = \&Loop_single;
    shift->Loop();
}

if ($Event::VERSION >= .03) {
    # Event >= 0.03
    *doOneEvent = \&Event::Loop::doOneEvent
} else {
    # Event <= 0.02
    *doOneEvent = \&Event::DoOneEvent
}

################################################# without threads

# WARNING: please do not call this directly!
use vars qw($Timer $Checkpoint);
sub indir_checkpoint {
    my ($class, $continue) = @_;
    checkpoint($continue);
    $Checkpoint=0;
    if ($continue) {
	if (!$Timer) {
	    $Timer = Event->timer(after => $LoopTime,
				  callback => sub { ++$Checkpoint },
				  desc => "ObjStore::Serve checkpoint");
	} else {
	    $Timer->again;
	}
        # don't acquire any unnecessary locks!
    }
}

sub Loop_single {
    my ($o,$waiter) = @_;
    local $Status = 'abnormal';
    local $LoopLevel = $LoopLevel+1;
    ++$ExitLevel;
#    warn "Loop enter $LoopLevel $ExitLevel";
    if (!$Init) { &init_signals; ++$Init; }

    $o->indir_checkpoint(1) if !$TXN;
    while ($ExitLevel >= $LoopLevel) {
        eval {
            if ($waiter and $waiter->()) {
		exitloop('ok');
            } else {
                while (!$Checkpoint and !$TXN->is_aborted) { doOneEvent() }
            }
        };
        if ($@) { warn; $TXN->abort }
        $o->indir_checkpoint($ExitLevel);
    }

#    warn "Loop exit $LoopLevel $ExitLevel = $Status";
    $Status;
}

################################################# threads (single)

sub Loop_async {
    my ($Q) = @_;
    local $Status = 'abnormal';
    local $LoopLevel = $LoopLevel+1;
    ++$ExitLevel;
    warn 1;
    while ($ExitLevel >= $LoopLevel) {
	warn 1;
	begin 'update', sub {
	    # not thread-safe? XXX
#	    Event->timer(-after => $LoopTime, -callback => sub {
#			     $Q->enqueue(DATA => 0, PRIORITY => 1)
#			 });
	    # XXX
	    warn 1;
            start_transaction();
	    dotodo() if @TXready;
	    while (1) {
		my $do = $Q->dequeue;
		warn $do;
		last if !ref $do;  #checkpoint
		$do->();
	    }
	    warn 1;
	    before_checkpoint();
	    warn 1;
	};
	warn 1;
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
        {
	    # UNUSEABLE FOR UPDATES XXX

	    # can't lock here, otherwise nested looping
	    # can't switch transactions
#	    lock $TXOpen;
	    eval {
	        {
		    lock $TXOpen;
		    dotodo() if $TXOpen && @TXready;
		}
		doOneEvent();
	    };
	    if ($@) {
		warn;
		# can't XXX
#		my $tx = ObjStore::Transaction::get_current();
#		$tx->abort() if $tx;
	    }
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
            $tx ||= ObjStore::Transaction->new('global', 'read');
            start_transaction();
        };
        sleep $LoopTime;   #fractional? XXX
        do {
            lock $TXOpen;
	    before_checkpoint($tx);
	    if ($UseOSChkpt and !$tx->is_aborted and $tx->top_level) {
		$tx->checkpoint();
	    } else {
		$tx->commit();
		$tx = undef;
	    }
            after_checkpoint();
        };
    }
}

################################################# Exit

*exitloop = \&Event::Loop::exitLoop;

1;
__END__

=head1 NAME

    ObjStore::Serve - event loop integration

=head1 SYNOPSIS

=head1 DESCRIPTION

EXPERIMENTAL package to integrate ObjStore transactions with Event.
Implements dynamic transactions.

Great service is key.

=head1 SEE ALSO

C<Event>, C<ObjStore>

=cut
