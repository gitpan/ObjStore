use strict;
package ObjStore::notify;
use Carp;

sub import {
    no strict 'refs';
    shift;
    my $p = caller;
    for my $m (@_) {
	# add more intelligence for extra call tracking?
#	croak "can't find method $ {p}::do_$m" 
#	    unless defined *{"$ {p}::do_$m"}{CODE};
	*{"$ {p}::$m"} = sub { shift->notify(join($;, $m, @_), 'now'); () };
    }
}

1;

=head1 NAME

ObjStore::notify - Pragma to Declare Methods That Will Execute Remotely

=head1 SYNOPSIS

  package MyObject;
  use ObjStore;
  use base 'ObjStore::HV';

  use ObjStore::notify qw(jump);
  sub do_jump {
     my ($obj, $why) = @_;     # server side
     warn $why; # 'very high'
  }

  $obj->jump('very high'); #client side

=head1 DESCRIPTION

Declares a simple stub method that invokes the C<notify> method.
Works in concert with C<ObjStore::Process::autonotify>.

There will probably be a way to alias this package to 'notify', so you
can 'use notify'.

=cut
