# the path to -*-perl-*- databases!
use Test;
BEGIN { plan tests => 15 }
use ObjStore;

srand(0);  # de-randomize
my @C = ('a'..'z');
sub dolevel {
    my ($level, $obj) = @_;
    $obj ||= ObjStore::AV->new('transient');
    for (0..8) {
	if ($level and $_ == 0) {
	    $obj->STORE($_, dolevel($level-1, ObjStore::AV->new($obj)));
	} elsif ($level and $_ == 1) {
	    $obj->STORE($_, dolevel($level-1, ObjStore::HV->new($obj)));
	} else {
	    $obj->STORE($_, $C[int rand @C].$C[int rand @C]);
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
2, 3, 4,5,6,7,8	2=vw, 3=qf, 4=qr, 5=fw, 6=oh, 7=gl, 8=ga	vwqfqrfwohglga
0/1/2, 1/5		0/1/2=ch, 1/5=in	chin
0/1/2, 3/5,5		0/1/2=ch, 3/5, 5	ch
1/bar/snark		1/bar/snark
2,2,2,2,2,2,2,2		/too many keys/
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
