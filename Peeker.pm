# factor to TIEHANDLE?

package ObjStore::Peeker;
use strict;
use Carp;
use IO::Handle;
use ObjStore ':ADV';
use vars qw($debug);

sub debug {
    my $ret = $debug;
    $debug = shift;
    $ret;
}

sub new {
    my ($class, @opts) = @_;
    my $o = bless {
	vareq => 0,
	prefix => '',
	indent => '  ',
	sep => "\n",
	addr => 0,
	refcnt => 0,
	summary_width => 3,
	width => 30,
	depth => 20,
	to => 'string',
	all => 0,
	pretty => 1,
    }, $class;
    $o->reset;
    croak "Odd number of parameters" if @opts & 1;
    while (@opts) {
	my ($k, $v) = (shift @opts, shift @opts);
	if (!exists $o->{$k}) { carp "Attribute '$k' unrecognized"; next; }
	$o->{$k} = $v;
    }
    $o;
}

sub reset {
    my ($o) = @_;
    $o->{seen} = {};
    $o->{coverage} = 0;
    $o->{serial} = 1;
}

sub reset_class {
    my ($o, $cl) = @_;
    $cl = ref $cl if ref $cl;
    delete $o->{seen}{$cl};
}

sub Peek {
    my ($o, $top) = @_;
    $o->{_level} = 0;
    $o->{has_sep} = 0;
    $o->{has_prefix} = 0;
    $o->{output} = '';
    $o->o('$fake'.$o->{serial}." = ") if $o->{vareq};
    $o->peek_any($top);
    $o->nl;
    ++ $o->{serial};
    $o->{output};
}

sub PercentUnused { die "wildy inaccurate metric no longer supported"; }

sub Coverage {
    my ($o) = @_;
    $o->{coverage};
}

sub prefix {
    my $o = shift;
    carp "prefix is depreciated; simply use ->o";
    $o->o(@_);
}

sub indent {
    my ($o, $code) = @_;
    ++ $o->{_level};
    $code->();
    -- $o->{_level};
}

sub nl {
    my ($o, $rep) = @_;
    $rep ||= 1;
    return if $o->{has_sep};
    $o->o($o->{sep} x $rep);
    $o->{has_sep}=1;
    $o->{has_prefix}=0;
}

# convert with *STDOUT{IO} notation
sub o {
    my $o = shift;
    if (!$o->{has_prefix}) {
	$o->{has_prefix}=1;
	$o->o($o->{'prefix'}, $o->{'indent'} x $o->{_level});
    }
    $o->{has_sep}=0;
    my $t = ref $o->{to};
    if (!$t) {
	if ($o->{to} eq 'string') {
	    $o->{output} .= join('', @_);
	} elsif ($o->{to} eq 'stdout') {
	    for (@_) { print };
	} else {
	    die "ObjStore::Peeker: Don't know how to write to $o->{to}";
	}
    } elsif ($t eq 'CODE') {
	$o->{to}->(@_);
    } elsif ($t->isa('IO::Handle') or $t->isa('FileHandle')) {
	$o->{to}->print(join('',@_));
    } else {
	die "ObjStore::Peeker: Don't know how to write to $o->{to}";
    }
}

sub peek_any {
    my ($o, $val) = @_;

    # interrogate
    my $type = reftype $val;
    my $class = blessed $val;
    my $basic_type;

    if (!$type) {
	if (!defined $val) {                $o->o('undef,');  }
	elsif ($val =~ /^-?\d+(\.\d+)?$/) { $o->o("$val,");   }
	else {				    $o->o("'$val',"); } # quoting? XXX
	++ $o->{coverage};
	return;
    }

    warn "peek_any($val): type=$type; class=$class\n" if $debug;

    if ($class) {
	for my $t (qw(Database Ref Cursor)) {
	    if ($val->isa("ObjStore::$t")) {
		$basic_type = "ObjStore::$t";
		last;
	    }
	}
	warn "basic_type=$basic_type\n" if $debug && $basic_type;
    }

    my $addr = "$val";
    my $name = $o->{addr} ? $addr : ($class or $type);
    if ($o->{refcnt} and $class and $val->can("_refcnt")) {
	$name .= " (".join(',', $val->_refcnt).")";
    }
    $o->{seen}{$class} ||= 0 if $class;

    if ($o->{_level} > $o->{depth} or defined($o->{seen}{$addr})) {
	$o->o("$name ...");
	++ $o->{coverage};
	return;
    }
    $o->{seen}{$addr}=1;
    ++ $o->{seen}{$class} if $class;
#    $name .= " (".$o->{seen}{$class}.")";

    if ($class and $basic_type and !$o->{pretty}) {
	my $m = "$basic_type\::POSH_PEEK";
	$val->$m($o, $name);
    } elsif ($class and $o->{pretty} and $val->can('POSH_PEEK')) {
	$val->POSH_PEEK($o, $name);
    } elsif ($type eq 'ARRAY') {
	$o->peek_array($val, $name);
    } elsif ($type eq 'HASH') {
	$o->peek_hash($val, $name);
    } elsif ($type eq 'REF') {
	++ $o->{coverage};
	$o->o('\ ');
	$o->peek_any($$val);
    } elsif ($type eq 'SCALAR') {
	++ $o->{coverage};
	$o->o($name);
    } else {
	die "Unknown type '$type'";
    }
}

sub peek_array {
    my ($o, $val, $name) = @_;
    my $blessed = blessed($val);
    my $len = ($blessed and $val->can("_count"))? $val->_count : @$val;
    $o->{coverage} += $len;
    my $big = $len > $o->{width};
    my $limit = $big? $o->{summary_width} : $len;
    
    $o->o($name . " [");
    $o->nl;
    $o->indent(sub {
	for (my $x=0; $x < $limit; $x++) {
	    $o->peek_any($val->[$x]);
	    $o->nl;
	}
	if ($big) {
	    $o->o("...");
	    $o->nl;
	}
    });
    $o->o("],");
    $o->nl;
}

sub peek_hash {
    my ($o, $val, $name) = @_;
    my @S;
    my $x=0;
    while (my($k,$v) = each %$val) {
	++ $o->{coverage};
	last if $x++ > $o->{width}+1;
	push(@S, [$k,$v]);
    }
    @S = sort { $a->[0] cmp $b->[0] } @S;
    my $big = @S > $o->{width}-1;
    my $limit = $big ? $o->{summary_width}-1 : $#S;
    
    $o->o($name . " {");
    $o->nl;
    $o->indent(sub {
	for $x (0..$limit) {
	    my ($k,$v) = @{$S[$x]};
	    
	    $o->o("$k => ");
	    $o->peek_any($v);
	    $o->nl;
	}
	if ($big) {
	    $o->o("...");
	    $o->nl;
	}
    });
    $o->o("},");
    $o->nl;
}

1;
