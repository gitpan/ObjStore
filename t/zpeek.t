# You might need to use GNU diffutils to see differences in -*-perl-*-
# output due to nulls.

use Test;
BEGIN { todo tests => 3 }

use Carp;
use IO::File;
use ObjStore;
use ObjStore::Peeker;
use lib './t';
use test;

&open_db;

begin 'update', sub { $db->gc_segments() };
die if $@;

begin 'update', sub {
    my $j = $db->root('John');
    my $before = $j->{size} || 0;
    my $now = 0;
    map { $now += $_->size } $db->get_all_segments;
    ok($before == $now) or 
	warn("SIZE MISMATCH ($before != $now); PLEASE RERUN TESTS\n");
    $j->{size} = $now;
};
die if $@;

chdir("t") or die "chdir t: $!";
my $fh = new IO::File;
$fh->open(">peek.out") or die "open(peek.out): $!";

#ObjStore::debug qw(bridge txn);

begin sub {
    my $p = new ObjStore::Peeker(addr => 0, refcnt => 1);
    my $dump = $p->Peek($db);
    $dump =~ s/^.*size =>.*$//m;
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
	    ok(1);
	} else {
	    ok(0);
	}
    } else {
	ok(system("mv $new $old")==0);
    }
}

check("peek.out", "peek.good");
