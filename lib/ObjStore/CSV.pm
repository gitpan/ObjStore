use strict;
# This will probably be rewritten.

package ObjStore::CSV;
use Carp;
use IO::File;
use vars qw(@EXPORT);
require Exporter;
*import = \&Exporter::import;
@EXPORT = qw(print_csv parse_csv);

# think about quoting XXX
# order-by asc/dec
sub print_csv {
    my $top = shift;

    my $st = { 
	      fh => *STDOUT{IO},
	      sep => "\t",
	      endl => "\n",
	      title => 0,
	      row => 0,
	      skip => 0,
	      max => 15500,  #excel friendly?
	      calc => {},
	      # column ordering?
    };

    croak "print_csv: odd number of args (@_)" if @_ & 1;
    for (my $a=0; $a < @_; $a+=2) {
	my ($k,$v) = @_[$a,$a+1];
	croak "print_csv: unknown param '$k'" if !exists $st->{$k};
	$st->{$k} = $v;
    }

    my $skipsave = $st->{skip};
    my $typehead;

    my $dorow;
    $dorow = sub {
	my ($k,$v) = @_;
	if (!$st->{title}) {	#first row
	    ++ $st->{title};
	    $st->{cmap} = {};

	    # sort columns here
	    my @k;
	    if ($v->isa('ObjStore::AVHV')) {
		my $kmap = $v->[0];
		@k = grep(!$kmap->is_system_field($_), keys %$kmap);
	    } else {
		@k = keys %$v;
	    }
	    for my $k (@k, keys %{$st->{calc}}) { $st->{cmap}{$k} = 0 }

	    $st->{cols} = [sort keys %{$st->{cmap}}];
	    for (my $z=0; $z < @{$st->{cols}}; $z++) {
		$st->{cmap}{ $st->{cols}[$z] } = $z;
	    }

	    $st->{fh}->print(join($st->{sep},$typehead,
				  @{$st->{cols}}).$st->{endl});
	}
	if (@_) {	#body row
	    ++ $st->{row};
	    my @z;
	    if ($v->isa('ObjStore::AVHV')) {
		my $kmap = $v->[0];
		while (my ($rk, $rx) = each %$kmap) {
		    next if $kmap->is_system_field($rk);
		    my $rv = $v->[$rx];
		    if (!exists $st->{cmap}{$rk}) {
			$st->{cmap}{$rk} = @{$st->{cols}};
			push(@{$st->{cols}}, $rk);
		    }
		    $z[$st->{cmap}{$rk}] = ref $rv? "$rv" : $rv;
		}
	    } else {
		while (my ($rk, $rv) = each %$v) {
		    if (!exists $st->{cmap}{$rk}) {
			$st->{cmap}{$rk} = @{$st->{cols}};
			push(@{$st->{cols}}, $rk);
		    }
		    $z[$st->{cmap}{$rk}] = ref $rv? "$rv" : $rv;
		}
	    }
	    while (my ($col,$sub) = each %{$st->{calc}}) {
		$z[$st->{cmap}{$col}] = $sub->($v);
	    }
	    @z = map { defined $_? $_ : 'undef' } @z;
	    # calculated columns
	    $st->{fh}->print(join($st->{sep}, $k, @z).$st->{endl});

	} else {		#last row
	    $st->{fh}->print(join($st->{sep},$skipsave + $st->{row},
				  @{$st->{cols}}).$st->{endl});
	}
    };

#	$st->{fh}->print("No records.\n");

    if ($top->isa('ObjStore::HV')) {
	$typehead = 'key';
	while (my($k,$v) = each %$top) {
	    if ($st->{skip}) { --$st->{skip}; next; }
	    $dorow->($k, $v);
	    last if $st->{row} > $st->{max}
	}
	$dorow->();

    } elsif ($top->isa('ObjStore::AV') or $top->isa('ObjStore::Index')) {
	$typehead = 'index';
	my $arlen = $top->can("_count")? $top->_count() : scalar(@$top);
	for (my $x=0; $x < $arlen; $x++) {
	    if ($st->{skip}) { --$st->{skip}; next; }
	    my $r = $top->[$x];
	    $dorow->($x, $r);
	    last if $st->{row} > $st->{max};
	}
	$dorow->();

    } else {
	croak "convert_2csv($top): don't know how to convert";
    }
}

# use anonymous package? XXX
package ObjStore::CSV::Parser;

sub at {
    my ($o) = @_;
    my $file = $o->{file}? $o->{file} : 'STDIN';
    " at $file line $o->{line}";
}

sub line { shift->{line} }

package ObjStore::CSV;

sub parse_csv {
    my $st = bless {
	      fh => *STDIN{IO},
	      file => undef,
	      sep => "\t",
	      cols => [],
	      to => [],
	      undef_ok => 0,
	      line => 0,
		   }, 'ObjStore::CSV::Parser';
    croak "parse_csv: odd number of args (@_)" if @_ & 1;
    for (my $a=0; $a < @_; $a+=2) {
	my ($k,$v) = @_[$a,$a+1];
	croak "parse_csv: unknown param '$k'" if !exists $st->{$k};
	$st->{$k} = $v;
    }
    if ($st->{file}) {
	$st->{fh} = new IO::File;
	$st->{fh}->open($st->{file}) or die "open $st->{file}: $!";
    }
    my $fh = $st->{fh};
    my $split = "[$st->{sep}]+";
    my $to = ref $st->{to};
    while (defined(my $l = <$fh>)) {
	++ $st->{line};
	my @l = split(m/$split/, $l);  #should handle quoted sep chars XXX
	# strip quotes
	for my $e (@l) {
	    $e =~ s/^\"(.*)\"$/$1/;
	    $e =~ s/^\'(.*)\'$/$1/;
	}
	if (! @{$st->{cols}}) {
	    $st->{cols} = \@l;
	    next;
	}
	carp "Missing columns".$st->at
	    if !$st->{undef_ok} && @l < @{$st->{cols}};
	my %row;
	for (my $c=0; $c < @{$st->{cols}}; $c++) {
	    $row{ $st->{cols}[$c] } = $l[$c];
	}
	if ($to eq 'CODE') { $st->{to}->(\%row, $st); }
	elsif ($to eq 'ARRAY') { push(@{$st->{to}}, \%row); }
    }
    $st->{to};
}

1;
