use strict;
package ObjStore::Job::Table;
use ObjStore;
use Event 0.05;
use base 'ObjStore::Table3';
use ObjStore::Serve qw(txretry meter);
use builtin qw(max min);           # available via CPAN
use vars qw($VERSION $Interrupt $WorkLevel $RunningJob);
$VERSION = '0.02';

require ObjStore::Job;

sub new { shift->SUPER::new(@_)->evolve; }

sub evolve {
    my ($o) = @_;
    $$o{SELF} ||= $o->new_ref($o,'hard');
    $$o{nextid} ||= 1;

    # Number of slices to do before returning to the event loop.
    # <20 means that high-priority time-sliced jobs will never get
    # their full share.
    $$o{quantum} ||= 33;

    $o->add_index('id', sub { ObjStore::Index->new($o, path => 'id') });

    # might contain only runnable jobs?
    $o->add_index('priority', sub { ObjStore::Index->new($o, path => 'priority', unique=>0 ) });
    $o;
}

sub restart {
    my ($o) = @_;
    my $allref = $o->index('priority')->new_ref('transient','hard');
    txretry(sub {
		my $all = $allref->focus;
		for my $j (@$all) {
		    $$j{cpu} = 0 if $$j{cpu};
		    $$j{state} = 'S' if $$j{state} eq 'R';
		}
	    });

    # this should be (more) configurable
    my $jref = $o->new_ref('transient','hard');
    my $worker;
    my $work = 0;
    $worker = Event->idle(desc => 'ObjStore::Job::Table',
			  callback => sub {
			      ++$work;
			      meter('ObjStore::Job::Table->work');

			      my $left = $jref->focus->work();

			      # need more slices?
			      $worker->again if $left <= 0;
			  });

    Event->timer(-interval => 1, -callback => sub { $worker->again },
		 -desc => "ObjStore::Job::Table timer");
    Event->timer(-interval => 3, -callback => sub {
		     $worker->{callback}->() if !$work;
		     $work = 0;
		 },
		 -desc => "ObjStore::Job::Table FORCE");
}

# Assumes one Job::Table per database.
#
# Jobs:
# - interruptable (non-preemptively)
# - cannot span transactions
# - cannot be nested
#
# A slice is the smallest unit of work worth the overhead of the
# job management apparatus.

sub _run1job {
    use integer;
    my ($j,$max) = @_;
    $RunningJob = $j->new_ref('transient','hard');
    my $used = $max - min $j->do_work($max), $max;
    $RunningJob = undef;
    $$j{cpu} = $used;
    $$j{state} = 'R' if $used && $$j{state} eq 'S';
    $$j{state} = 'L' if $used == 0 && $$j{state} eq 'R';
    $used;
}

$WorkLevel = 0;
sub work {
    use integer;
    my ($o) = @_;
    my $slices = int $$o{quantum};
    my $priorities = $o->index('priority');
    return $slices if $WorkLevel || !@$priorities;

    local $WorkLevel = 1;
    begin 'update', sub {
	local $Carp::Verbose = 1;
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
	if (!$RunningJob) {
	    warn $@;  #real bug!!
	} else {
	    my $j = $RunningJob->focus();
	    $RunningJob = undef;
	    $j->{'why'} = $@;
	    $j->{state} = 'K';
	    return 0;  #retry immediately
	}
	$slices = 0;  #did work and also lost it!
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
