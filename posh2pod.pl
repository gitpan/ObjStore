#!/usr/local/bin/perl -w

my $esc = sub {
    my $c = shift;
    return 'E<lt>' if $c eq '<';
    return 'E<gt>' if $c eq '>';
};

my $nl=0;

while (defined(my $l = <>)) {
    chomp $l;
    next if $l =~ m/^\s*$/;
    if ($l =~ m/\%/) {
	$l =~ s/([><])/$esc->($1)/ge;
	$l =~ m/^(.*)\%\s*(.*)$/;
	$l = "\nC<I<$1%> B<$2>>";
	print "$l\n";
	$nl ++;
    } else {
	print "\n" if $nl;
	print "  $l\n";
	$nl=0;
    }
}
