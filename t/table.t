#-*-perl-*-
BEGIN { $| = 1; $tx=1; print "1..1\n"; }
BEGIN { require 5.00452; }

use ObjStore;
use lib './t';
use test;

&open_db;

require ObjStore::Table;
require Row;

try_update {
    $db->verify_class_fields;

    my $john = $db->root('John');
    die "No john" if !$john;

    my $tbl = $john->{table} = new ObjStore::Table($john, 30);
    my $ar = $tbl->array;
    for (my $x=0; $x < 20; $x++) {
	my $r = new Row($tbl);
	$r->{f1} = $x ** 1;
	$r->{f2} = $x ** 2;
	$r->{f3} = "This is big ".($x ** 3);
	$ar->[$x] = $r;
    }
    $ar->[16] = $ar->[14];
    $ar->[23] = new Row($tbl);

    $tbl->new_index('Field', 'e1', 'f1');
    $tbl->new_index('Field', 'e2', 'f2');
    $tbl->new_index('Field', 'big', 'f3');

    $tbl->index('e1')->build;
    $tbl->index('e2')->build;
    $tbl->index('big')->build;
};

try_update {
    my $john = $db->root('John');
    die "No john" if !$john;

    delete $john->{table};
};

ok;
