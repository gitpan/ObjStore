# This is obviously -*-perl-*- dontcha-think?

BEGIN { $| = 1; $tx=1; print "1..2\n"; }
sub ok { print "ok $tx\n"; $tx++; }
sub not_ok { print "not ok $tx\n"; $tx++; }

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

package main;
use strict;
use ObjStore;

my $osdir = ObjStore->schema_dir;
my $DB = ObjStore::Database->open($osdir . "/perltest.db", 0, 0666);
    
try_update {
    my $john = $DB->root('John');
    $john ? ok : not_ok;
    
    $john->{obj} = new PTest($DB);
};
die if $@;

try_update {
    my $john = $DB->root('John');
    $john->{obj}->bonk ? ok : not_ok;
};
print "[Abort] $@\n" if $@;
