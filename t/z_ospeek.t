# Because of embedded null support in -*-perl-*-, you might need to
# use GNU diffutils for good diagnostics.
BEGIN { $| = 1; $tx=1; print "1..2\n"; }

use Carp;
use IO::File;
use ObjStore;
use ObjStore::Peeker;
use lib './t';
use test;

&open_db;

chdir("t") or die "chdir t: $!";
my $fh = new IO::File;
$fh->open(">peek.out") or die "open(peek.out): $!";

#ObjStore::debug qw(bridge txn);

begin sub {
    my $p = new ObjStore::Peeker(addr => 0, refcnt => 1);
    my $dump = $p->Peek($db);
    $dump =~ s/^.*junk_seg =>.*$//m;
    $dump =~ s/^.*__VERSION__.*$//m;
    $dump =~ s/TestDB\[.*?\]/TestDB/m;
    print $fh $dump;
    $count = $p->Coverage;
    print $fh "count = $count\n";
};
$fh->close;

# Also see module 'Test::Output'
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
