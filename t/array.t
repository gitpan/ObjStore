#-*-perl-*-
BEGIN { $| = 1; $tx=1; print "1..5\n"; }

sub ok { print "ok $tx\n"; $tx++; }
sub not_ok { print "not ok $tx\n"; $tx++; }

use ObjStore;

my $DB = ObjStore::open(ObjStore->schema_dir . "/perltest.db", 0, 0666);
try_update {
    my $john = $DB->root('John');
    $john? ok:not_ok;
    my $a = $john->{'array'} = new ObjStore::AV($DB);

    $a->[0] = 1.5;
    {
	use integer;
	$a->[1] = 2;
    }
    $a->[2] = "string";
    $a->[3] = [qw(a b c)];
    $a->[4] = {zip => $a};
    for my $x (1..10) { $a->[$x + 4] = $x }
};
print "[Abort] $@\n" if $@;

try_read {
    my $john = $DB->root('John');
    my $a = $john->{'array'};
    ($a->[0] == 1.5 and
     $a->[1] == 2 and
     $a->[2] eq "string")? ok:not_ok;
    $a->[3][1] eq 'b' ? ok:not_ok;
    "$a->[4]{zip}" eq "$a" ? ok:not_ok;
};
print "[Abort] $@\n" if $@;

try_update {
    my $john = $DB->root('John');
    delete $john->{'array'};
    ok;
};
print "[Abort] $@\n" if $@;
