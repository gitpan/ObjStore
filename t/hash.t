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
#    tied %$xr ? ok : not_ok;  #XXX
    
    $xr->{blat} = 69;
#    $john->{nest}{rat}{blat} == 69 ? ok : not_ok; #XXX
    
    delete $john->{nest}{rat}{blat};
    delete $john->{nest}{rat};
    delete $john->{nest};
    
    defined $john->{nest} ? not_ok : ok;
};

sub zero {
    my $h = shift;
    $h->{''} = 'zero';
    $h->{''} eq 'zero' ? ok:not_ok;
}

begin 'update', sub {
    my $john = $db->root('John');
    zero($john);
#    zero($john->{dict});  BROKEN XXX
};
