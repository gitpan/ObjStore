package ObjStore::AppInstance;
use strict;
use ObjStore;
use ObjStore::Config;
use Carp;

sub ROOT() { 'instances' }

sub new {
    my ($class, $app, @opts) = @_;
    my $dbdir = $ENV{"\U${app}_DBDIR"} || TMP_DBDIR;
    $dbdir =~ s,/+?$,,;
    my $wdb = ObjStore::open("$dbdir/$app", 0, 0666);
    my $o = bless { _wdb => $wdb, _app => $app, _cached => 0 }, $class;
    $o->config(@opts);
}

sub wdb { $_[0]->{_wdb} }

sub config {
    my $o = shift @_;
    croak "Odd number of args in $o->config()" if @_ & 1;
    my %opts = @_;
    while (my ($k,$v) = each %opts) {
	if ($k eq 'pvars') {
	    $o->{_pvars} = $v;
	} else {
	    croak("$o->config($k => $v) unknown parameter");
	}
    }
    $o;
}

sub pvars {
    my ($o) = @_;
    @{$o->{_pvars}}, 'state', 'public';
}

sub sid {
    my $o = shift;
    die "$o->sid must be overridden";
}

sub now {
    my ($sec,$min,$hour,$mday,$mon,$year) = localtime;
    $mon++; $year+=1900;
    sprintf("%4d%02d%02d%02d%02d", $year, $mon, $mday, $hour, $min);
}

sub cache {
    my ($o) = @_;
    croak "Already cached" if $o->{_cached};

    my $r = $o->wdb->root(ROOT, sub{new ObjStore::HV($o->wdb, 100)});

    my @pvars = $o->pvars;
    if (!exists $r->{$o->sid}) {
	my $s = $o->wdb->create_segment($o->sid);
	my $ses = $r->{$o->sid} = new ObjStore::HV($s, scalar(@pvars)+5);
	$ses->{public} = {
	    ctime => $o->now,
	    segment => $s->get_number,
	};
    }
    my $ses = $r->{$o->sid};
    for my $k (@pvars) { $o->{$k} = $ses->{$k}; }
    $o->{_cached} = 1;
}

sub uncache {
    my ($o, $modified) = @_;
    croak "Already uncached" if !$o->{_cached};

    my $txn = ObjStore::Transaction::get_current();
    if ($txn and $txn->get_type ne 'read') {

	$o->{public}{mtime} = $o->now if $modified;

	# unhook persistent state
	my $ses = $o->wdb->root(ROOT)->{$o->sid};
	die "no session" if !$ses;
	for my $k ($o->pvars) {
	    $ses->{$k} = $o->{$k};
	}
    }
    for my $k ($o->pvars) { delete $o->{$k} if ref $o->{$k}; }
    $o->{_cached} = 0;
}

sub destroy {
    my ($o) = @_;
    $o->uncache if $o->{_cached};
    delete $o->wdb->root(ROOT)->{$o->sid};  #need to slow down? XXX
}

1;

=head1 NAME

  ObjStore::AppInstance - A helper class for interactive ObjStore tools.

=head1 SYNOPSIS

  use base 'ObjStore::AppInstance';

  sub new {
    my ($class) = @_;
    my $o = $class->SUPER::new('app-name', pvars => [qw(ttype pref view)]);
    ...
    $o
  }

=head1 DESCRIPTION

Sessions contain both transient and persistent data.

The persistent data can only be accessed within a transaction but
transient data is always available.

=head1 METHODS

=over 4

=item * cache

=item * uncache

=item * destroy

=back

=head1 TODO

Make it an ObjStore::Table.

Identify sessions with hostname/pid or custom keys and garbage collect
if unused for long enough.

=cut
