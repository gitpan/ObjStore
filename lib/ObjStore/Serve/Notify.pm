use strict;
package ObjStore::Serve::Notify;
use Event 0.28;
use ObjStore;
use ObjStore::Serve;
use vars qw($OVERFLOW);

my $notifyEv;
sub init_autonotify {
    die "autonotify already invoked"
	if $notifyEv;
    my ($Q) = @_;
    my $cb = ($Q? sub { $Q->enqueue(DATA => \&dispatch_notifications,
				    PRIORITY => 2) }
	      : \&dispatch_notifications);
    $notifyEv = Event->io(e_desc => 'ObjStore::Serve::Notify',
			  e_fd => ObjStore::Notification->_get_fd(),
			  e_poll => 'r', e_cb => $cb);
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
	    my @args = split /$;/, $why, -1;
	    my $call = shift @args;
	    warn "$f->$call(".join(', ',@args).")\n"
		if $osperlserver::Debug{n};
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
