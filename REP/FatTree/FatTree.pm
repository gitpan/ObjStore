# To make this a shared library, simply remove
# newXS("ObjStore::REP::FatTree::bootstrap",...) from ObjStore.xs
# and let the DynaLoader take care of it.

use strict;
package ObjStore::REP::FatTree;
require ObjStore::PathExam::Path;

use base 'DynaLoader';
__PACKAGE__->bootstrap($ObjStore::VERSION);

$ObjStore::SCHEMA{'ObjStore::REP::FatTree'}->
    load($ObjStore::Config::SCHEMA_DBDIR."/REP-FatTree-01.adb");

package ObjStore::REP::FatTree::Index;
use Carp;
# We don't want this package in the @ISA because that would break the
# representation abstraction.  The consequence is extra pain to do
# method calls.

# make recursive!
sub estimate {
    # EXPERIMENTAL
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
# ]

sub configure {
    my $o = shift;
    my $c = $o->ObjStore::REP::FatTree::Index::_conf_slot();
    $c ||= (__PACKAGE__.'::Conf')->new($o, [1,1,[],1]);
    return $c if @_ == 0;
    my @conf = ref $_[0] ? %{$_[0]} : @_;
    while (@conf) {
	my $k = shift @conf;
	croak "$o->configure: no value found for key '$k'" if !@conf;
	my $v = shift @conf;
	if ($k eq 'unique') {
	    $c->[1] = $v;
	} elsif ($k eq 'path') {
	    $c->[2] = ObjStore::PathExam::Path->new($c, $v);
	} elsif ($k eq 'size' or $k eq 'type') {
	} elsif ($k =~ m/^excl(usive)?$/) {
	    carp "non-exclusive indices are no longer supported";
	} else {
	    carp "$o->configure: unknown parameter '$k'";
	}
    }
    $o->ObjStore::REP::FatTree::Index::_conf_slot($c);
}

sub index_path {
    my ($o) = @_;
    my $c = $o->ObjStore::REP::FatTree::Index::_conf_slot();
    return if !$c;
    $c->[2]
}

package ObjStore::REP::FatTree::Index::Conf;
use base 'ObjStore::AV';
use vars qw($VERSION);
$VERSION = '1.00';

sub POSH_PEEK {
    my ($c, $p) = @_;
    # should use method call XXX
    $p->o("(".ObjStore::PathExam::Path::stringify($c->[2]).")".
	  ($c->[1] ? ' UNIQUE' : ''));
}

1;
__END__

What makes insert slow?

- keys not copied (could be optimized by hand coding push/unshift)

- relaxed depth recalc

- rotations
