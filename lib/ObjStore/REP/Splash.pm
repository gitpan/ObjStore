use strict;
package ObjStore::REP::Splash;
use base 'DynaLoader';
'ObjStore::REP::Splash'->bootstrap($ObjStore::VERSION);

package ObjStore::REP::Splash::Heap;
use Carp;

# [
#   version=0
#   [
#     ['key1','key2'],
#     ...
#   ],
#   descending=0,
# ]

sub configure {
    my $o = shift;
    my $c = ObjStore::REP::Splash::Heap::_conf_slot($o);
    $c ||= [0,[],0];
    return $c if @_ == 0;
    my @C = ref $_[0] ? %{$_[0]} : @_;
    while (@C) {
	my $k = shift @C;
	croak "$o->configure: no value for '$k'" if !@C;
	my $v = shift @C;
	if ($k eq 'path') {
	    my @comp = split m",\s*", $v;
	    croak "$o->configure(path=>'$v'): invalid" if @comp==0;
	    croak "$o->configure(path=>'$v'): too many keys" if @comp >= 8;
	    $c->[1] = [map {[map {"$_\0"} split(m"\/", $_)]} @comp];
	} elsif ($k eq 'descending') {
	    $c->[2] = $v;
	} elsif ($k eq 'ascending') {
	    $c->[2] = !$v;
	} else {
	    carp "$o->configure: unknown parameter '$k'";
	}
    }
    bless $c, 'ObjStore::REP::Splash::Heap::Conf';
    ObjStore::REP::Splash::Heap::_conf_slot($o, $c);
}

package ObjStore::REP::Splash::Heap::Conf;
use base 'ObjStore::AV';

sub POSH_PEEK {
    my ($c, $p) = @_;
    my @ps;
    my $paths = $c->[1];
    # FACTOR XXX
    $paths->map(sub {
		    my @p;
		    my $path = shift;
		    $path->map(sub { chop(my $s = shift); push(@p, $s) });
		    push(@ps, join('/', @p));
		});
    $p->o("(".join(', ', @ps).")");
}

1;
