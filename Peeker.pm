# create persistent Peekers?
package ObjStore::Peeker;
use strict;
use Carp;
use vars qw{
    $vareq
    $prefix
	$indent
	    $sep
		$addr
		    $refcnt
			$summary_width
			    $instances
				$width
				    $depth
					$to
					    $all
					    };
$vareq=0;
$prefix='';
$indent='  ';
$sep="\n";
$addr=0;
$refcnt=0;
$summary_width=3;
$instances=3;
$width=30;
$depth=20;
$to='string';
$all=0;

sub new {
    my ($class, @opts) = @_;
    my $o = bless {
	serial => 1,
	vareq => 0,
	prefix => $prefix,
	indent => $indent,
	sep => $sep,
	addr => $addr,
	refcnt => $refcnt,
	summary_width => $summary_width,
	instances => $instances,
	width => $width,
	depth => $depth,
	to => $to,
	all => $all,
    }, $class;
    croak "Odd number of parameters" if @opts & 1;
    while (@opts) { $o->{pop @opts} = pop @opts }
    $o;
}

sub Peek {
    my ($o, $top) = @_;
    $o->{output} = '';
    $o->{seen} = {};
    $o->{level} = 0;
    $o->{has_sep} = 0;
    $o->{has_prefix} = 0;
    $o->{coverage} = 0;
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
    my ($o) = @_;
    return if $o->{has_prefix};
    $o->o($o->{prefix}, $o->{indent} x $o->{level});
    $o->{has_prefix}=1;
}

sub nl {
    my ($o) = @_;
    return if $o->{has_sep};
    $o->o($o->{sep});
    $o->{has_sep}=1;
}

sub o {
    my $o = shift;
    $o->{has_sep}=0;
    $o->{has_prefix}=0;
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

sub avg {
    if (@_) {
	my $sum=0;
	for (@_) { $sum += $_ }
	$sum / @_;
    } else { 0 }
}

sub peek_any {
    my ($o, $val) = @_;

    # interrogate
    my $type = ObjStore::reftype $val;
    my $class = ref $val;
    my $blessed = $class ne $type;

    # Since persistent-bless might be tweaked... ? XXX
    $class = $val->_blessed_to if ($class and $class->isa('ObjStore::UNIVERSAL'));

    if (!$class) {
	if (!defined $val) {
	    $o->o('undef,');
	} elsif ($val =~ /^-?\d+(\.\d+)?$/) {
	    $o->o("$val,");
	} else {
	    # do special quoting? XXX
	    $o->o("'$val',");
	}
	++ $o->{coverage};
	return;
    }

    my $addr = "$val";
    my $name = $o->{addr} ? $addr : $class;
    if ($o->{refcnt} and $blessed and $val->can("_refcnt")) {
	$name .= " (".join(',', $val->_refcnt).")";
    }
    $o->{seen}{$class} ||= 0;

    if ($o->{level} > $o->{depth} or defined($o->{seen}{$addr}) or
	($blessed and $val->can('_is_blessed') and
	 $val->_is_blessed and $o->{seen}{$class} > $o->{instances})) {
	$o->o("$name ...");
	++ $o->{coverage};
	return;
    }
    $o->{seen}{$addr}=1;
    ++ $o->{seen}{$class};

    $o->prefix;
    if ($blessed and $val->can('peek')) {
	$val->peek($o, $name);
    } elsif ($type eq 'ARRAY') {
	$o->peek_array($val, $name);
    } elsif ($type eq 'HASH') {
	$o->peek_hash($val, $name);
    } elsif ($type eq 'SCALAR') {
	++ $o->{coverage};
	$o->o($name);
    } else {
	die "Unknown type '$type'";
    }
}

sub peek_array {
    my ($o, $val, $name) = @_;
    my $blessed = ref($val) ne ObjStore::reftype($val);
    my $len = ($blessed and $val->can("_count"))? $val->_count : @$val;
    $o->{coverage} += $len;
    my $big = $len > $o->{width};
    my $limit = $big? $o->{summary_width} : $len;
    
    $o->o($name . " [");
    $o->nl;
    ++$o->{level};
    for (my $x=0; $x < $limit; $x++) {
	$o->prefix;
	$o->peek_any($val->[$x]);
	$o->nl;
    }
    if ($big) {
	$o->prefix;
	$o->o("...");
	$o->nl;
    }
    --$o->{level};
    $o->prefix;
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
    ++$o->{level};
    for $x (0..$limit) {
	my ($k,$v) = @{$S[$x]};
	
	$o->prefix;
	$o->o("$k => ");
	$o->{has_prefix}=1;
	$o->peek_any($v);
	$o->nl;
    }
    if ($big) {
	$o->prefix;
	$o->o("...");
	$o->nl;
    }
    --$o->{level};
    $o->prefix;
    $o->o("},");
    $o->nl;
}

1;
