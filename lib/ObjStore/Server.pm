use strict;
package ObjStore::Server;
use Carp;
use ObjStore;
use base 'ObjStore::HV';
use vars qw($EXE $HOST $SELF);

$EXE = $0;
$EXE =~ s{^ .* / }{}x;
chop($HOST = `hostname`);

# Should start rather low until it is established that there
# are no other servers running.
$ObjStore::TRANSACTION_PRIORITY = 0x2000;

# Auto-retry of deadlocks can cause havoc.  You must take
# responsibility to address this yourself.
ObjStore::set_max_retries(0);

# Big program style.
ObjStore::fatal_exceptions(0);

sub new {
    my $o = shift->SUPER::new(@_);
    $$o{exe} = $EXE;
    $$o{argv} = \@ARGV;
    $$o{host} = $HOST;
    $$o{pid} = $$;
    $$o{uid} = getpwuid($>);
    $$o{mtime} = time;
    $SELF = $o->new_ref('transient','safe');
    $o;
}

sub touch {
    my ($class, $time) = @_;
    $time ||= time;
    if ($SELF and $SELF->deleted()) {
	return if defined wantarray;
	warn "another server started up";
	exit;
    }
    my $s = $SELF->focus;
    $$s{mtime} = $time;
    $s;
}

1;

=head1 NAME

    ObjStore::Server - associate a Unix process with a database

=head1 SYNOPSIS

=head1 DESCRIPTION

The minimum amount of database code to reasonably represent a Unix
process.  Patches for non-Unixen welcome.

=cut
