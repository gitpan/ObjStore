use strict;
package ObjStore::Serve::Notify;
use IO::Handle;
use Event;
use ObjStore;
use ObjStore::Serve qw(meter);
use vars qw($OVERFLOW);

my $notifyEv;
sub init_autonotify {
    die "autonotify already invoked"
	if $notifyEv;
    my ($Q) = @_;
    my $fh = IO::Handle->new();
    $fh->fdopen(ObjStore::Notification->_get_fd(), "r");
    my $cb = ($Q? sub { $Q->enqueue(DATA => \&dispatch_notifications,
				    PRIORITY => 2) }
	      : \&dispatch_notifications);
    $notifyEv = Event->io(desc => 'ObjStore::Serve::Notify',
			  -handle => $fh, -events => 'r',
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