use strict;
package ObjStore::Job::Table;
use ObjStore;
require Event;
use base 'ObjStore::Table3';
use builtin qw(max min);           # available via CPAN
use vars qw($VERSION $Interrupt $WorkLevel $RunningJob);
$VERSION = '0.02';

require ObjStore::Job;

sub new { shift->SUPER::new(@_)->evolve; }

sub evolve {
    my ($o) = @_;
    $$o{SELF} ||= $o->new_ref($o,'hard');
    # Number of slices to do before returning to the event loop.
    # <20 means that high-priority time-sliced jobs will never get
    # their full share.
    $$o{quantum} ||= 33;
    $$o{nextid} ||= 1;

    $o->add_index('id', sub { ObjStore::Index->new($o, path => 'id') });
    # might contain only runnable jobs?
    $o->add_index('priority',
		  sub { ObjStore::Index->new($o, path => 'priority', unique=>0 ) });
    $o;
}

sub restart {
    my ($o) = @_;
    my $jref = $o->new_ref('transient','hard');
    my $worker;
    $worker = sub {
	my $left = $jref->focus->work();
	Event->idle($worker) if $left <= 0;  # need more slices!
    };
    Event->timer(-interval => 1, -callback => sub { Event->idle($worker) });
}

# assumes one Job::Table per database
# interruptable (non-preemptively)
# cannot span transactions
# cannot be nested
# a slice is the smallest unit of work worth the overhead of a method call

sub _run1job {
    my ($j,$max) = @_;
    $RunningJob = $j->new_ref('transient','hard');
    my $used = $max - min $j->do_work($max), $max;
    $RunningJob = undef;
    $$j{state} = 'R' if $used && $$j{state} eq 'S';
    $$j{state} = 'L' if $used == 0 && $$j{state} eq 'R';
    $used;
}

$WorkLevel = 0;
sub work {
    my ($o) = @_;
    my $slices = int $$o{quantum};
    my $priorities = $o->index('priority');
    return $slices if $WorkLevel || !@$priorities;

    local $WorkLevel = 1;
    begin 'update', sub {
	$Interrupt = 0;
	my @todo = @$priorities; #snapshot

	# high priority
	while ($slices > 0 and !$Interrupt and 
	       @todo and $todo[0]->{priority} <= 0) {
	    my $j = shift @todo;
	    $slices -= _run1job($j, $slices) if $j->running;
	}

	# time-sliced
	my @ts;
	while (@todo and $todo[0]->{priority} <= 20) {
	    my $j = shift @todo;
	    push @ts, $j if $j->running;
	}
	while (@ts) {
	    my @ready = @ts;
	    @ts=();
	    while ($slices > 0 and !$Interrupt and @ready) {
		my $j = shift @ready;
		my $max = min 21 - $$j{priority}, $slices;
		$slices -= _run1job($j,$max);
		push @ts, $j if $$j{state} eq 'R';
	    }
	}
	
	# low priority idle jobs
	while ($slices > 0 and !$Interrupt and @todo) {
	    my $j = shift @todo;
	    $slices -= _run1job($j,$slices) if $j->running;
	}
    };
    if ($@) {
	my $j = $RunningJob->focus();
	if (!$j) {
	    warn $@;  #real bug!!
	} else {
	    $j->{'why'} = $@;
	    $j->{state} = 'K';
	    return 0;  #retry immediately
	}
	$slices = 0;  #did work and also lost it!
    } else {
	ObjStore::Process->meter('idle') if $slices > 0;
    }
    $slices
}

sub find_jobs {
    my ($o, $type) = @_;
    my @match;
    my $x = $o->index('id');
    for my $j (@$x) { push @match, $j if $j->isa($type) }
    @match;
}

1;
