# This -*-perl-*- is autoloaded!

package PTest;
use strict;
use ObjStore;
use vars qw(@ISA);
@ISA = qw(ObjStore::HV);

sub new {
    my ($class, $where) = @_;
    my $o = $class->SUPER::new($where, 10);
    $o->{is} = 1;
    bless $o, $class;
}

sub bonk {
    my $o = shift;
    $o->{is};
}

1;
