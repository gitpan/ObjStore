# path to -*-perl-*-
use Test; plan tests => 15;
use ObjStore;
require ObjStore::PathExam::Path;

srand(0);  # de-randomize
my @C = ('a'..'z');
sub dolevel {
    my ($level, $obj) = @_;
    $obj ||= ObjStore::AV->new('transient');
    for my $at (0..8) {
	if ($level and $at == 0) {
	    my $below = dolevel($level-1, ObjStore::AV->new($obj));
	    $obj->STORE($at, $below);
	} elsif ($level and $at == 1) {
	    $obj->STORE($at, dolevel($level-1, ObjStore::HV->new($obj)));
	} else {
	    $obj->STORE($at, $C[int rand @C].$C[int rand @C]);
	}
    }
    $obj;
}
my $junk = dolevel(8);

my $tests=q[
			/invalid/
4			4=qr		qr
9			9
1/4			1/4=vs		vs
2, 3, 4,5	2=vw, 3=qf, 4=qr, 5=fw	vwqfqrfw
0/1/2, 1/5		0/1/2=ch, 1/5=in	chin
0/1/2, 3/5,5		0/1/2=ch, 3/5, 5	ch
1/bar/snark		1/bar/snark
2,2,2,2,2		/too many keys/
0/0/0/0/0/0/0/0/0	/too long/
];

my $exam = ObjStore::PathExam->new();

for my $test (split /\n/, $tests) {
    next if !$test;
    my ($path, $expect, $keys) = split /\t+/, $test;
    eval {
	my $p = ObjStore::PathExam::Path->new('transient', $path);
	$exam->load_path($p);
	$exam->load_target($junk);
    };
    ok $@? $@ : $exam->stringify(), $expect, $path;
    if (!$@) {
	my $kx = join '', $exam->keys();
	ok $kx, $keys if $kx;
    }
}
