package Eval::Context;
use strict;

sub new {
    my ($class, $file, $offset) = @_;
    my ($die, $warn) = @SIG{'__DIE__', '__WARN__'};
    $SIG{'__DIE__'} = sub {
	if ($_[0] =~ m/^(.*) at \(eval \d+\) line (\d+)/s) {
	    die "$1 at $file line ".($offset + $2).".\n";
	} else {
	    die "XXX ".$_[0];
	}
    };
    $SIG{'__WARN__'} = sub {
	if ($_[0] =~ m/^(.*) at \(eval \d+\) line (\d+)/s) {
	    warn "$1 at $file line ".($offset + $2).".\n";
	} else {
	    warn "XXX ".$_[0];
	}
    };
    bless sub { $SIG{'__DIE__'} = $die; $SIG{'__WARN__'} = $warn; }, $class;
}

sub DESTROY { &{$_[0]}(); }

package Eval;
use strict;
use Carp;
use vars qw($VERSION);

$VERSION = '1.00';

sub new {
    my ($class, $code, $file, $offset) = @_;
    my $o = bless { ok=>0 }, $class;
    if (@_ == 4) {
	$o->eval($code, $file, $offset);
    } elsif (@_ == 1) {
	# ok
    } else {
	croak "new Eval([code, file, offset])";
    }
    $o;
}

sub eval {
    my ($o, $code, $file, $offset) = @_;
    $o->{ok} = 0;
    $o->{file} = $file;
    $o->{offset} = $offset;
    {
	my $ctxt = new Eval::Context($o->{file}, $o->{offset});
	$o->{thunk} = CORE::eval $code;
    }
    die if $@;
    $o->{ok} = 1;
}

sub ok { $_[0]->{ok} }

sub x { 
    my $o = shift @_;
    my $ctxt = new Eval::Context($o->{file}, $o->{offset});
    &{$o->{thunk}}(@_);
}

1;

=head1 NAME

Eval - Adjusts warnings and errors for C<eval>d code

=head1 SYNOPSIS

    require Eval;

    my $code = new Eval();
    $code->eval($code_string, $file, $line);
    my $result = $code->x(args, ...);

=head1 DESCRIPTION

Eval is a simple wrapper around the C<eval> built-in that adjusts
warnings and error messages.  You may pass in a C<file> and C<line>,
in addition to the code to be evaluated.

=head1 BUGS

Allow customization of message mangling?  This is similar to
Religion.pm in some ways?

Regression test...?

=head1 AUTHOR

Copyright (c) 1997 Joshua Nathaniel Pritikin.  All rights reserved.

This package is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut
