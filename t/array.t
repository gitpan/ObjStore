#-*-perl-*-
BEGIN { $| = 1; $tx=1; print "1..5\n"; }

sub ok { print "ok $tx\n"; $tx++; }
sub not_ok { print "not ok $tx\n"; $tx++; }

use ObjStore;
#use Devel::Peek qw(Dump SvREFCNT);

my $DB = ObjStore::open(ObjStore->schema_dir . "/perltest.db", 0, 0666);
try_update {
    my $john = $DB->root('John');
    $john? ok:not_ok;
    my $a = $john->{'array'} = new ObjStore::AV($DB);

    my $fatty = $john->{'fatty'} = new ObjStore::AV($DB);
    $fatty->[0] = 1;
    $fatty->[100] = 100;

    $a->[0] = 1.5;
    { use integer; $a->[1] = 2; }
    $a->[2] = "string";
    $a->[3] = [qw(a b c)];
#    $a->[4] = {zip => $a};
    $a->[4] = {};
    $a->[4]{zip} = $a;

    for my $x (1..10) { $a->[$x + 4] = $x }
};

try_read {
    my $john = $DB->root('John');
    my $a = $john->{'array'};
    ($a->[0] == 1.5 and
     $a->[1] == 2 and
     $a->[2] eq "string")? ok:not_ok;
    $a->[3][1] eq 'b' ? ok:not_ok;
    "$a->[4]{zip}" eq "$a" ? ok:not_ok;
};

try_update {
    my $john = $DB->root('John');
    $john->{'array'}[4] = undef;  #break circular link
    delete $john->{'array'};
    ok;
};
