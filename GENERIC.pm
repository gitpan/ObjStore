# To make this a shared library, simply remove
# newXS("ObjStore::GENERIC::bootstrap",...) from ObjStore::bootstrap
# and let the DynaLoader take care of it.

package ObjStore::GENERIC;
bootstrap ObjStore::GENERIC $ObjStore::VERSION;

package ObjStore::AV;
use Carp;

sub new {
    my ($this, $loc, $rep, @REST) = @_;
    $loc = $loc->segment_of;
    $class = ref($this) || $this;
    if (!defined $rep) {
	&{$REP{splash_array}}($class, $loc, 7, @REST);

    } elsif (ref $rep) {
	my $av = &{$REP{splash_array}}($class, $loc, scalar(@$rep)||7, @REST);
	for (my $x=0; $x < @$rep; $x++) { $av->STORE($x, $rep->[$x]); }
	@$rep = ();  #must avoid leaving junk in transient memory
	$av;

    } elsif ($rep =~ /^\d+(\.\d+)?$/) {
	&{$REP{splash_array}}($class, $loc, $rep, @REST);
    } elsif (!$rep) {
	croak "$class->new(loc,rep): defined but false rep";
    } else {
	if (ref $REP{$rep} eq 'CODE') {
	    &{$REP{$rep}}($class, $loc, @REST);
	} else {
	    croak "$class->new(loc,rep): unknown rep '$rep'";
	}
    }
}

package ObjStore::HV;
use Carp;

sub new {
    my ($this, $loc, $rep, @REST) = @_;
    $loc = $loc->segment_of;
    $class = ref($this) || $this;
    if (!defined $rep) {
	&{$REP{splash_array}}($class, $loc, 7, @REST);

    } elsif (ref $rep) {
	my ($total) = split(m'/', scalar %$rep);
	my $hv = &{$REP{splash_array}}($class, $loc, $total || 7, @REST);
	while (my($hk,$v) = each %$rep) { $hv->STORE($hk, $v); }
	%$rep = ();  #must avoid leaving junk in transient memory
	$hv;

    } elsif ($rep =~ /^\d+(\.\d+)?$/) {
	confess "$rep < 1" if $rep < 1;
	if ($rep < 25) {
	    &{$REP{splash_array}}($class, $loc, $rep, @REST);
	} else {
	    &{$REP{os_dictionary}}($class, $loc, $rep, @REST);
	}
    } elsif (!$rep) {
	croak "$class->new(loc,rep): defined but false rep";
    } else {
	if (ref $REP{$rep} eq 'CODE') {
	    &{$REP{$rep}}($class, $loc, @REST);
	} else {
	    croak "$class->new(loc,rep): unknown rep '$rep'";
	}
    }
}

1;
