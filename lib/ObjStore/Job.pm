use strict;
package ObjStore::Job;
use ObjStore;
use base 'ObjStore::HV';  #use fields XXX
use vars qw($VERSION);
$VERSION = '0.01';

# Job States:
#
# R running
# L infinite loop detected
# S sleeping                - will retry every second
# T suspended
# D done
# K killed

sub new {
    # $id should be probably be formed with:
    #    join('.', `hostname`, $$, $id++);

    my ($class, $near, $id, $priority) = @_;
    my $t = $near->database_of->hash->{jobs};
    my $o = shift->SUPER::new($t);
    # $id is a string!
    if ($id) { $$o{id} = "$id"; }
    else {     $$o{id} = "$$t{nextid}"; ++$$t{nextid}; }
    $$o{priority} = defined $priority? $priority : 10;
    $$o{job_table} = $$t{SELF};
    $$o{state} = 'R';
    $$o{why} = '';
    $t->add($o);
    $o;
}

sub runnable {
    my $state = shift->{state};
    $state ne 'D' and $state ne 'K';
}
sub running {
    my $state = shift->{state};
    $state eq 'R' or $state eq 'S';
}

use ObjStore::notify qw(work set_priority signal acknowledge);
sub do_work {
    my ($o, $slices) = @_;
    # override this method!
    my $used = int rand 8;
    warn "$o->work(): consuming $used slices";
    $slices - $used;  # how many left
}
sub do_set_priority {
    my ($o, $pri) = @_;
    my $t = $$o{job_table}->focus;
    $t->remove($o);
    $$o{priority} = $pri;
    $t->add($o);
    ()
}
sub do_signal {
    my ($o, $sig) = @_;
    return if !$o->runnable;
    if    ($sig eq 'kill')      { $$o{state} = 'K'; $$o{why} = 'signal'; }
    elsif ($sig eq 'suspend')   { $$o{state} = 'T'; }
    elsif ($sig eq 'resume')    { $$o{state} = 'R'; }
    else { warn "$o->signal($sig): unknown signal"; }
    ()
}
sub do_acknowledge {  #like wait(2)
    my ($o) = @_;
    return if $o->runnable;
    $$o{job_table}->focus->remove($o);
    ()
}

package ObjStore::Job::Table;
use ObjStore;
require Event;
use base 'ObjStore::Table3';
use builtin qw(max min);           # available via CPAN
use vars qw($VERSION $Interrupt $WorkLevel $RunningJob);
$VERSION = '0.01';

sub evolve {
    my ($o) = @_;
    $$o{SELF} ||= $o->new_ref($o,'hard');
    #number of slices to do before returning to the event loop
    $$o{quantum} ||= 42;
    $$o{nextid} ||= 1;

    $o->add_index('id', sub { ObjStore::Index->new($o, path => 'id') });
    # might contain only runnable jobs?
    $o->add_index('priority',
		  sub { ObjStore::Index->new($o, path => 'priority', unique=>0 ) })
}

sub restart {
    my ($o) = @_;
    my $jref = $o->new_ref('transient','hard');
    my $worker;
    $worker = sub {
	my $left = $jref->focus->work();
	Event->idle($worker) if $left <= 0;
    };
    Event->timer(-interval => 1, -callback => $worker);
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
    $$j{state} = 'L' if $used == 0 && $$j{state} eq 'R';
    $used;
}

$WorkLevel = 0;
sub work {
    my ($o) = @_;
    my $slices = int $$o{quantum};
    return $slices if $WorkLevel;
    local $WorkLevel = 1;

    my $priorities = $o->index('priority');
    return $slices if !@$priorities;
    begin 'update', sub {
	$Interrupt = 0;
	my $todo = $priorities->new_cursor();
	$todo->moveto(-1);

	# high priority
	while ($slices > 0 and !$Interrupt) {
	    my $j = $todo->each(1);
	    return $slices if !$j;
	    next unless $j->running;
	    my $pri = $$j{priority};
	    if ($pri <= 0) {
		$slices -= _run1job($j, $slices);
	    } else {
		$todo->step(-1);
		last;
	    }
	}

	# time-sliced
	my @ts;
        {
	    my $j;
	    while ($j = $todo->each(1) and $$j{priority} <= 20
		   and $j->running) { push @ts, $j; }
	}
	$todo->step(-1);
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
	while ($slices > 0 and !$Interrupt) {
	    my $j = $todo->each(1);
	    last if !$j;
	    next unless $j->running;
	    $slices -= _run1job($j,$slices);
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
    }
    $slices
}

1;

=head1 NAME

ObjStore::Job - Non-Preemptive Idle-Time Job Scheduler

=head1 SYNOPSIS

=head1 DESCRIPTION

The whole scheduling operation occurs within a single transaction.
While this means that any job can kill the entire transaction, this
seems a better choice than wrapping every job in its own
mini-transaction.  Since transactions are relatively expensive, it is
assumed that most of the time all jobs will complete without error.

=head1 SCHEDULING PRIORITIES

=over 4

=item * HIGH PRIORITY <= 0

Allowed to consume all available pizza slices.

=item * TIME-SLICED 1-20

Given pizza slices proportional to the priority until either all the
pizza slices are consumed or all the jobs are asleep.

=item * IDLE > 20

Given all remaining pizza slices.

=back

=head1 BUGS

Too bad you can't store CODEREFs in the database.

Time does not necessarily transmute into pizza.

=cut
