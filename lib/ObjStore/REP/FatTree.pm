# To make this a shared library, simply remove
# newXS("ObjStore::REP::FatTree::bootstrap",...) from ObjStore.xs
# and let the DynaLoader take care of it.

use strict;
package ObjStore::REP::FatTree;
bootstrap ObjStore::REP::FatTree $ObjStore::VERSION;

# We don't want this package in the @ISA because that would break the
# representation abstraction.  The consequence is extra pain to do
# method calls.

package ObjStore::REP::FatTree::Index;
use Carp;

# make recursive!
sub estimate {
    my ($type, $count, $fill) = @_;
    if ($type eq 'ObjStore::Index') {
	{ 
	    pkg => 'ObjStore::REP::FatTree::Index',
	    bytes => 6462,
	    fill => .734,
	    struct => [qw(OSPV_fatindex dextv_tn)],
	}
    }
}

# [
#   version=1,
#   is_unique=1,
#   [
#     ['field1','field2'],
#     ...,
#   ],
#   exclusive readonly=0  (v1)
# ]

sub configure {
    my $o = shift;
    my $c = $o->ObjStore::REP::FatTree::Index::_conf_slot();
    $c ||= [1,1,[],1];
    return $c if @_ == 0;
    my @conf = ref $_[0] ? %{$_[0]} : @_;
    while (@conf) {
	my $k = shift @conf;
	croak "$o->configure: no value found for key '$k'" if !@conf;
	my $v = shift @conf;
	if ($k eq 'unique') {
	    $c->[1] = $v;
	} elsif ($k eq 'path') {
	    my @comp = split(m",\s*", $v);
	    croak("$o->configure(path=>'$v'): invalidate") if @comp==0;
	    croak("$o->configure(path=>'$v'): too many keys") if @comp >= 8;
	    $c->[2] = [map {[map {"$_\0"} split(m"\/", $_)]} @comp];
	    
	} elsif ($k eq 'size' or $k eq 'type') {
	} elsif ($k =~ m/^excl(usive)?$/) {
	    $c->[3] = $v;
	} else {
	    carp "$o->configure: unknown parameter '$k'";
	}
    }
    bless $c, 'ObjStore::REP::FatTree::Index::Conf';
    $o->ObjStore::REP::FatTree::Index::_conf_slot($c);
}

package ObjStore::REP::FatTree::Index::Conf;
use base 'ObjStore::AV';
use vars qw($VERSION);
$VERSION = '1.00';

# goofy because arrays don't work XXX
sub POSH_PEEK {
    my ($c, $p) = @_;
    my @ps;
    my $paths = $c->[2];
    $paths->map(sub {
		    my @p;
		    my $path = shift;
		    $path->map(sub { chop(my $s = shift); push(@p, $s) });
		    push(@ps, join('/', @p));
		});
    $p->o("(".join(', ', @ps).")". ($c->[1] ? ' UNIQUE' : ''));
}

1;