#-*-perl-*-
BEGIN { $| = 1; $tx=1; print "1..7\n"; }

use ObjStore;
use lib './t';
use test;

#use Devel::Peek qw(Dump SvREFCNT);
#ObjStore::debug qw(PANIC);

&open_db;
begin 'update', sub {
    my $john = $db->root('John');
    $john? ok:not_ok;
    my $a = $john->{'array'} = new ObjStore::AV($db);

    my $fatty = $john->{'fatty'} = new ObjStore::AV($db);
    $fatty->[0] = 1;
    $fatty->[100] = 100;

    $a->[0] = 1.5;
    { use integer; $a->[1] = 2; }
    $a->[2] = "string";
    $a->[3] = [qw(a b c)];
    $a->[4] = [];
    $a->[4] = {};
    $a->[4]{zip} = $a;

    for my $x (1..10) { $a->[$x + 4] = $x }
};

begin sub {
    my $john = $db->root('John');
    my $a = $john->{'array'};
    ($a->[0] == 1.5 and
     $a->[1] == 2)? ok:not_ok;
    if ($a->[2] ne "string") {
	print "ObjStore: " . join(" ", unpack("c*", $a->[2])) . "\n";
	print "perl:     " . join(" ", unpack("c*", "string")) . "\n";
	not_ok;
    } else {ok}
    $a->[3][1] eq 'b' ? ok:not_ok;
    "$a->[4]{zip}" eq "$a" ? ok:not_ok;
};

begin 'update', sub {
    my $john = $db->root('John');
    $john->{'array'}[4] = undef;  #break circular link
    delete $john->{'array'};
    ok;
};

