#-*-perl-*-
BEGIN { $| = 1; $tx=1; print "1..1\n"; }

sub ok { print "ok $tx\n"; $tx++; }
sub not_ok { print "not ok $tx\n"; $tx++; }

use Carp;
use IO::File;
use ObjStore;
use ObjStore::Peeker;

ObjStore::_enable_blessings(0);

my $db = ObjStore::open(ObjStore->schema_dir . "/perltest.db", 0, 0666);

chdir("t") or die "chdir t: $!";
my $fh = new IO::File;
$fh->open(">peek.out") or die "open(peek.out): $!";

try_read {
    my $p = new ObjStore::Peeker(all => 1, addr => 0);
    my $dump = $p->Peek($db);
    $dump =~ s/^.*cnt =>.*$//m;
    $dump =~ s/^.*seg =>.*$//m;
    print $fh $dump;
    $count = $p->Coverage;
    print $fh "count = $count\n";
};
$fh->close;

# also see Test::Output
sub check {
    my ($new,$old) = @_;
    if (-e $old) {
	if (system("diff $old $new")==0) {
	    unlink $new;
	    ok;
	} else {
	    not_ok;
	}
    } else {
	system("mv $new $old")==0? ok:not_ok;
    }
}

check("peek.out", "peek.good");
