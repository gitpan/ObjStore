#-*-perl-*-
BEGIN { $| = 1; $tx=1; print "1..4\n"; }

use ObjStore;
use lib './t';
use test;

&open_db;    
try_update {
    my $john = $db->root('John');
    $john ? ok : not_ok;
    
    my $xr = $john->{nest}{rat} = {};
    tied %$xr ? ok : not_ok;
    
    $xr->{blat} = 69;
    $john->{nest}{rat}{blat} == 69 ? ok : not_ok;
    
    delete $john->{nest}{rat}{blat};
    delete $john->{nest}{rat};
    delete $john->{nest};
    
    defined $john->{nest} ? not_ok : ok;
};
