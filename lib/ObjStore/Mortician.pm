use strict;
package ObjStore::Mortician;
use ObjStore;
use base 'ObjStore::HV';
use vars qw($VERSION);
$VERSION = '0.02';

sub import {
    # allow keepalive customization?
    my $p = caller;
    no strict 'refs';
    *{"$ {p}::NOREFS"} = sub {
	my ($carcass) = @_;
	# slow but how else?
	my $o = $carcass->database_of->hash->{'ObjStore::Mortician'};
	if ("$carcass" eq $$o{'next'}) {
#	    warn "burning $carcass ".$carcass->_refcnt;
	    return;
	}
	die "can't find myself" if !$o;
	my $q = $$o{hades};
	# prefer to use cached time... XXX
	push @$q, time, $carcass;
#	warn "embalming $carcass ".$carcass->_refcnt;
    };
}

sub new { shift->SUPER::new(@_)->evolve; }

sub evolve {
    my ($o) = @_;
    $$o{keepalive} ||= 30;  #minimum keepalive time
    $$o{hades} ||= ObjStore::AV->new($o, 20);
    if (my $j = $$o{job}) {
	if (!$j->runnable or !$j->is_evolved) {
	    $j->cancel;
	    delete $$o{job};
	}
    }
    $$o{job} ||= ObjStore::Mortician::Job->new($o);
    $$o{'next'} = '';
    $o;
}

package ObjStore::Mortician::Job;
use ObjStore;
use base 'ObjStore::Job';
use vars qw($VERSION);
$VERSION = '0.01';

sub NOREFS {}  #suicide perhaps, but you can't be your own mortician!

sub new {
    my ($class, $mort) = @_;
    my $o = $class->SUPER::new($mort, '', 100);
    $$o{mortician} = $mort;
    $o;
}

sub do_signal {
    my ($o, $sig) = @_;
    return if $sig eq 'kill';    # (saving throw... made!)
    $o->SUPER::do_signal($sig);
}

sub do_work {
    my ($j,$slices) = @_;
    my $now = time; #again XXX
    my $o = $$j{mortician};
    my $q = $$o{hades};
    $$j{state} = 'S';
    while ($slices > 0 and @$q and $now - $$q[0] > $$o{keepalive}) {
	$slices -= 50;     #more?
	shift @$q;
	$$o{'next'} = "$$q[0]";  # slow :-(
	shift @$q;               # final destruction
    }
    $slices;
}

1;
__END__

=head1 NAME

ObjStore::Mortician - Delay Physical Destruction of Persistent Objects

=head1 SYNOPSIS

    package MySlowlyDeletedClass;
    use ObjStore::Mortician;

=head1 DESCRIPTION

This hook should not be used unless it cannot be avoided.  There is a
significant performance penalty compared to immediate destruction.
However, one good reason to use this mechanism is to ease the
syncronization constraints when multiple processes are allowed to send
notifications through objects that might be deleted without
anticipation or forewarning (ie. ghost objects :-).

Default delay is 60 seconds.

=cut
