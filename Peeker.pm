package ObjStore::Peeker;
use strict;
use Carp;
use vars qw($LinePrefix $LineIndent $LineSep
	    $Addr $SummaryWidth $MaxWidth $MaxDepth $MaxInstances
	    $To $All);

$LinePrefix='';
$LineIndent='  ';
$LineSep="\n";
$Addr=0;
$SummaryWidth=3;
$MaxWidth=20;
$MaxDepth=20;
$MaxInstances=3;
$To='string';
$All=0;

sub new {
    my ($class, %cnf) = @_;
    my $o = bless {
	prefix => $LinePrefix,
	indent => $LineIndent,
	sep => $LineSep,
	addr => $Addr,
	summary_width => $SummaryWidth,
	instances => $MaxInstances,
	width => 20,
	depth => 20,
	level => 0,
	seen => {},
	to => $To,
	all => $All,
	output => '',
	has_sep => 0,
	has_prefix => 0,
	pct_unused => [],
    }, $class;
    while (my ($k,$v) = each %cnf) { $o->{$k} = $v; }
    $o;
}

sub Peek {
    my $o = shift;
    for my $top (@_) { $o->_peek($top); }
    $o->{output};
}

sub PercentUnused {
    my ($o) = @_;
    my $count=0;
    my $sum=0;
    for my $h (@{$o->{pct_unused}}) {
	$count += $h->{card};
	$sum += $h->{card} * $h->{unused};
    }
    $count = -1 if $count == 0;
    ($sum, $count);
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
    if (!$t and $o->{to} eq 'string') {
	$o->{output} .= join('', @_);
    } elsif ($t eq 'CODE') {
	$o->{to}->(@_);
    } elsif ($t->isa('IO::Handle') or $t->isa('FileHandle')) {
	$o->{to}->print(join('',@_));
    } else {
	die "ObjStore::Peeker: Don't know how to write to $o->{to}";
    }
}

sub _peek {
    my ($o, $val) = @_;
    my $type = ObjStore::reftype $val;
    my $class = ref $val;

    # Since persistent blessing likely turned off...
    $class = $val->_ref if ($class and $class->isa('ObjStore::UNIVERSAL'));

    if (!$class) {
	if (!defined $val) {
	    $o->o('undef,');
	} elsif ($val =~ /^-?[1-9]\d{0,8}$/) {
	    $o->o("$val,");
	} else {
	    $val =~ s/([\\\'])/\\$1/g;
	    $o->o("'$val',");
	}
	return;
    }

    my $addr = "$val";
    my $name = $o->{addr} ? $addr : $class;
    $o->{seen}{$class} ||= 0;

    if ($o->{level} > $o->{depth} or $o->{seen}{$addr} or
	($class !~ /^ObjStore::/ and $o->{seen}{$class} > $o->{instances})) {
	if ($type eq 'HASH') {
	    $o->o("$name { ... }");
	} elsif ($type eq 'ARRAY') {
	    $o->o("$name [ ... ]");
	} elsif ($class->isa('ObjStore::Set')) {
	    $o->o("$name [ ... ]");
	} else {
	    $o->o("$class ...");
	}
	return;
    }
    $o->{seen}{$addr}=1;
    ++ $o->{seen}{$class};

    if ($val->can('cardinality') and $val->can('percent_unused')) {
	push(@{$o->{pct_unused}}, {card=>$val->cardinality,
				   unused=>$val->percent_unused});
    }

    $o->prefix;
    if ($class eq 'ObjStore::Database') {
	for my $r ($val->get_all_roots) {
	    next if (!$o->{all} and $r->get_name eq ObjStore::_PRIVATE_ROOT);

	    $o->prefix;
	    ++$o->{level};
	    $o->o("$r ",$r->get_name," = ");
	    $o->{has_prefix}=1;
	    $o->_peek($r->get_value);
	    --$o->{level};
	    $o->nl;
	}
    } elsif ($class->isa('ObjStore::Set')) {
	my @S;
	my $x=0;
	for (my $v=$val->first; $v; $v=$val->next) {
	    last if $x++ > $o->{width}+1;
	    push(@S, $v);
	}
	my $big = @S > $o->{width};
	my $limit = $big ? $o->{summary_width}-1 : @S;

	$o->o($name . " [");
	$o->nl;
	++$o->{level};
	for (my $v=$val->first; $v; $v=$val->next) {
	    last if $limit-- <= 0;
	    $o->prefix;
	    $o->_peek($v);
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
    } elsif ($type eq 'HASH') {
	my @S;
	my $x=0;
	while (my($k,$v) = each %$val) {
	    last if $x++ > $o->{width}+1;
	    push(@S, [$k,$v]);
	}
	@S = sort { $a->[0] cmp $b->[0] } @S;
	my $big = @S > 20;
	my $limit = $big ? $o->{summary_width}-1 : $#S;

	$o->o($name . " {");
	$o->nl;
	++$o->{level};
	for $x (0..$limit) {
	    my ($k,$v) = @{$S[$x]};

	    $o->prefix;
	    $o->o("$k => ");
	    $o->{has_prefix}=1;
	    $o->_peek($v);
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
    } elsif ($type eq 'ARRAY') {
	$o->o($name . " [ ?? ],");
    } else {
	die "Unknown type '$type'";
    }
}

1;
