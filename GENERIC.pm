# To make this a shared library, simply remove
# newXS("ObjStore::GENERIC::bootstrap",...) from ObjStore::bootstrap
# and let the DynaLoader take care of it.

package ObjStore::GENERIC;
bootstrap ObjStore::GENERIC $ObjStore::VERSION;

package ObjStore::AV;
use Carp;
use vars qw(@ISA %REP);
@ISA=qw(ObjStore::UNIVERSAL);

sub new {
    my ($class, $loc, $rep, @REST) = @_;
    if (!defined $rep) {
	&{$REP{splash_array}}($class, $loc, 7, @REST);
    } elsif ($rep =~ /^\d+$/) {
	&{$REP{splash_array}}(@_);
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
use vars qw(@ISA %REP);
@ISA=qw(ObjStore::UNIVERSAL);

sub new {
    my ($class, $loc, $rep, @REST) = @_;
    if (!defined $rep) {
	&{$REP{splash_array}}($class, $loc, 7, @REST);
    } elsif ($rep =~ /^\d+$/) {
	if ($rep < 20) {
	    &{$REP{splash_array}}(@_);
	} else {
	    &{$REP{os_dictionary}}(@_);
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

package ObjStore::Set;
use Carp;
use vars qw(@ISA %REP);
@ISA=qw(ObjStore::UNIVERSAL);
#use overload ('+=' => \&a,
#	      '-=' => \&r);

sub new {
    my ($class, $loc, $rep, @REST) = @_;
    if (!defined $rep) {
	&{$REP{splash_array}}($class, $loc, 7, @REST);
    } elsif ($rep =~ /^\d+$/) {
	if ($rep < 20) {
	    &{$REP{splash_array}}(@_);
	} else {
	    &{$REP{os_set}}(@_);
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

sub a { carp "depreciated; you must type 'add' instead of 'a'"; add(@_); }
sub r { carp "depreciated; you must type 'rm' instead of 'r'"; rm(@_); }

1;
