#-*-perl-*-
BEGIN { $| = 1; $tx=1; print "1..3\n"; }

use ObjStore;
use lib './t';
use test;

&open_db;    
begin 'update', sub {
    my $john = $db->root('John');
    die 'no john' if !$john;
    
    my $xr = $john->{nest}{rat} = {};
#    ok(tied %$xr);
    
    $xr->{blat} = 69;
#    ok($john->{nest}{rat}{blat} == 69);
    
    delete $john->{nest}{rat}{blat};
    delete $john->{nest}{rat};
    delete $john->{nest};
    
    ok(! defined $john->{nest});
};

sub zero {
    my $h = shift;
    $h->{''} = 'zero';
    ok($h->{''} eq 'zero');
}

begin 'update', sub {
    my $john = $db->root('John');
    zero($john);
#    zero($john->{dict});  BROKEN XXX
};
