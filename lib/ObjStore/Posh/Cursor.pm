use strict;
package ObjStore::Posh::Cursor;
use ObjStore;
use base 'ObjStore::HV';
use vars qw($VERSION);
$VERSION = '0.70';

sub new {
    my ($o) = shift->SUPER::new(@_);
    $$o{where} = [];   #stack of locations
    $$o{at} = 0;
    $o;
}

use ObjStore::notify qw(configure execute);
sub do_configure {
    my $o = shift;
    # local or remote?
}

sub myeval {
    my ($o, $perl) = @_;

    my $w = $o->{where}[ $$o{at} ];
    my @c = map { $_->focus } @$w;
    local($input::db, $input::at, $input::cursor) = 
	($o->database_of, @c? $c[$#$c] : $o->database_of, \@c);
    $$o{why} = '';

    my @r;
    my $to_eval = "no strict; package input;\n#line 1 \"input\"\n".$perl;
    if (wantarray) {               @r = eval $to_eval; }
    elsif (defined wantarray) { $r[0] = eval $to_eval; }
    else {                              eval $to_eval; }
    if ($@) {
	ObjStore::Transaction::get_current()->abort();
	$$o{why} = $@;
	()
    }
    if (!defined wantarray) { () } else { wantarray ? @r : $r[0]; }
}

sub resolve {
    my ($o,$to,$update) = @_;
    # $to already stripped of leading & trailing spaces
    $$o{why} = '';
    my $w = $$o{where};
    my @at = map { $_->focus } @{ $$w[ $$o{at} ] };
    if (!$to) {
	@at = ();
	if ($update) {
	    unshift @$w, [];
	    pop @$w if @$w > 5;
	    $$o{at} = 0;
	}
    } elsif ($to =~ m/^([+-])$/) {
	my $at = $1 eq '-' ? $$o{at}+1 : $$o{at}-1;
	if ($at >= 0 and $at < @$w) {
	    @at = map { $_->focus } @{ $$w[$at] };
	    if ($update) {
		$$o{at} = $at;
	    }
	}
    } elsif ($to =~ m,^[\w\/\.\:\-]+$,) {
	my @to = split m'/+', $to;
	for my $t (@to) {
	    next if $t eq '.';
	    if ($c eq '..') {
		pop @at if @at;
	    } else {
		my $at = $at[$#at];
		if ($at->can('POSH_CD')) {
		    $at = $at->POSH_CD($c);
		    $at = $at->POSH_ENTER()
			if blessed $at && $at->can('POSH_ENTER');
		    if (!blessed $at or !$at->isa('ObjStore::UNIVERSAL')) {
			$at = 'undef' if !defined $at;
			$$o{why} = "resolve($to): failed at $t (got '$at'!)";
			last;
		    }
		}
		push @at, $at;
	    }
	}
	if (!$$o{why} and $update) {
	    unshift @$w, [map { $_->new_ref($w,'hard') } @at];
	    pop @$w if @$w > 5;
	    $$o{at} = 0;
	}
    } else {
	my $at = $o->myeval($to);
	if (!$$o{why}) {
	    push @at, $at;
	    if ($update) {
		unshift @$w, [map { $_->new_ref($w,'hard') } @at];
		pop @$w if @$w > 5;
		$$o{at} = 0;
	    }
	}
    }
    @at? $at[$#$a] : undef;
}

sub do_execute {
    my ($o, $in) = @_;
    # use a fresh transaction: speed doesn't matter compared to safety
    begin sub {
	if ($in =~ m/^cd \b \s* (.*?) \s* $/sx) {
	    $o->resolve($1, 1);
	} elsif ($in =~ m/^(ls|peek|raw) \b \s* (.*?) \s* $/sx) {
	    my ($cmd,$to) = ($1,$2);
	    my @at;
	    if ($to) {
		@at = $o->resolve($to, 0);
	    } else {
		my $at = $o->{where}[ $$o{at} ];
		$at[0] = @$at ? $$at[ $#$at ]->focus : undef;
	    }
	    if (!$$o{why}) {
		my $depth = $cmd eq 'raw' || $cmd eq 'peek'? 10 : 0;
		my $p = ObjStore::Peeker->new(pretty => $cmd eq 'raw',
					      depth => $depth);
		$$o{out} = $p->Peek($at[0]);
	    }
	} elsif ($in eq 'pwd') {
	    my $out='';
	    my $p = ObjStore::Peeker->new(depth => 0);
	    for (my $z=0; $z < @$cursor; $z++) {
		$out .= '$cursor->['."$z] = ".$p->Peek($$cursor[$z]);
	    }
	    $$o{out} = $out;
	} else {
	    my @r = $o->myeval($in);
	    if (!$$o{why}) {
		my $p = ObjStore::Peeker->new(depth => 10, vareq => 1);
		my $out='';
		for (@r) { $out .= $p->Peek($_) }
		$$o{out} = $out;
	    }
	}
    };
    warn if $@;
}

package input;
use ObjStore ':ADV';
use vars qw($at $db $cursor);

package ObjStore::Posh::Remote;
use ObjStore;


1;
