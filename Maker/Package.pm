# Copyright (c) 1997 Joshua Nathaniel Pritikin.  All rights reserved.
# This package is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.

# Why does MakeMaker make use of standard unix make when it could use
# perl exclusively?  Does /bin/make actually add much value?  I hate the syntax too.

# Everything in here should be generic relative to the programming language.
# Extensive use of anonymous subs works quite nicely.

=head1 NAME

Maker - Yet Another Make-like Program

=head1 DESCRIPTION

Why yet another make?  I have never found a make program that I
thought was easy enough to use.  In fact, a year of two ago I wrote a
make package similar to this but it turned out too hard to use and I
ended up discarding it.  Here are some features that make this maker
unique:

=item Due to the adherence to object-oriented organization, multiple
targets can easily be built in the same be-file in a natural and
obvious manner.

=item Rules have two phases of execution.  Once when they are added
to the rule tree and once when they are executed.  The complete power
of perl is available at both times.  Rules do not need to be written
only in terms of pattern matching.  This makes for more organic, 
intelligent behavior.

=item The reliance of the rule selection engine is kept to an absolute
minimum.  Be-files state exactly what to do in a direct procedural
fashion.  The full power of perl is available to factor out duplicate
information.

=head1 TODO

=item A front-end needs to be designed to allow be-files to be
very short and simple.  I tend to think of the be-files as
a target language for a front-end preprocessor.  At least there
should be a script to get people up and compiling quick.

=item Makefile.PL translator & front-end for be-files.

=item Generate dependencies with makedepend and grok them.

=item RCS/SCCS/ClearCase support.

=item Parallel builds on multiple hosts.  (Should be easy.)

=item The documentation.

=head1 SYNOPSIS

=head1 AUTHOR

Joshua Pritikin, pritikin@mindspring.com

=head1 SEE ALSO

MakeMaker, /bin/make, gmake, nmake, imake, build, cook, plan9 make,
clearmake, ParallelMake, etc..

=cut

my $NEXT = 'aaa';

package Maker::Package;
use strict;
use Carp;
use Cwd;
use IO::File;
use FindBin qw($Bin);
use ExtUtils::Manifest qw(&mkmanifest &manicheck);
use File::Copy;
use File::Path;
use Getopt::Long;

use vars qw(@ISA $VERSION);
@ISA = qw(Maker::Target);
$VERSION = 2.00;

sub new {
    my ($class, %CNF) = @_;
    my $o = $class->SUPER::new();

    $o->{beline} = '[-nop] [-silent] [-verbose] cmd [...]';
    $o->{usage} = {};
    $o->{posthelp} = '';
    $o->{nop} = 0;
    $o->{verbose} = 1;
    $o->{clean} = [];
    $o->{spotless} = [];

    while (my ($k,$v) = each %CNF) {
	if ($k eq 'top') {
	    $o->{name} = $v;
	    $o->{top} = $Bin;
	} else {
	    croak "Unknown configuration $k => $v";
	}
    }

    $o->a('usage', sub {
	print "\nperl ./be $o->{beline}\n";
	for my $k (sort keys %{$o->{usage}}) {
	    print "  $k - $o->{usage}{$k}\n";
	}
	print "\n".$o->{'posthelp'} if length $o->{posthelp};
	exit;
    });
    $o->A('clean', 'Delete intermediate files.', sub {
	for my $yuck (@{$o->{clean}}) { $o->x('rm', glob($yuck)); }
    });
    $o->A('spotless', 'Delete all generated files.', sub {
	for my $yuck (@{$o->{clean}}, @{$o->{spotless}}) {
	    $o->x('rm', glob($yuck));
	}
    });
    $o->A('tested', 'Run regression tests.', sub {
	$o->top_go('_test');   #special per-target unit
    });
    $o->alias(test=>'tested');
    if ($o->{top}) {
	croak "Top-level must have a name" if !$o->{name};
	$o->a('automade', sub {
	    $o->top_go('clean');
	    $o->top_go('checked');
	    $o->top_go('made');
	    $o->top_go('tested');
	});
	$o->A('checked', "Verify that the package is complete.", sub {
	    print "Package $o->{name}-$o->{version} looks complete.\n" if ! manicheck;
	});
	$o->alias(check => 'checked');
	$o->A('manifest', "Update the ./MANIFEST file.", sub {
	    mkmanifest;
	});
	$o->A('installed', 'Copy files to final install area.', sub {
	    $o->top_go('_inst');   #special per-target unit
	    print "\nCongratulations!  $o->{name}-$o->{version} is installed.\n";
	});
	$o->A('uninstalled', 'Delete any files that were installed.', sub {
	    $o->top_go('_uninst'); #special per-target unit
	    print "As you wish...\n";
	});
	$o->alias(install => 'installed', uninstall => 'uninstalled');
	$o->A('dist', "Create a pkg.tar.gz distribution file.", sub {
	    die "version missing" if !$o->{version};
	    die "name missing" if !$o->{name};
	    $o->top_go('checked');
	    my $dir = cwd;
	    $dir =~ s|^.*/||;
	    my @all = `cat ./MANIFEST`;
	    chop @all;
	    my $all = join(' ', map { "$dir/$_" } @all);
	    $o->x("cd ..; tar -cf - $all | gzip -c > $o->{name}-$o->{version}.tar.gz");
	});
    }

    # stupid tricks :-)
    $o->a('happy', sub { print "Yes!\n"; });
    $o->a('love', sub {	print "Good idea.\n"; });
    $o->a('fun', sub { print "Sorry.  I'm just a stupid computer. :-(\n"; });
    $o->a('sexy', sub { print ":-)\n"; });

    $o;
}

sub A {
    croak "Maker::Package->A('cmd', 'usage', sub {})" if @_ != 4;
    my ($o, $tag, $usage, $code) = @_;
    $o->{usage}{$tag} = $usage;
    $o->a($tag, $code);
}

sub clean {
    my $o = shift;
    push(@{$o->{clean}}, @_);
}

sub spotless {
    my $o = shift;
    push(@{$o->{spotless}}, @_);
}

sub post_help {
    my ($o, $str) = @_;
    $o->{posthelp} .= $str;
}

# extend to work with RCS & SCCS magic - move to Rules? XXX
sub pm_2version {
    my ($o, $file) = @_;
    my $fh = new IO::File;
    $fh->open($file) or die "open $file: $!";
    my $ok=0;
    while (defined (my $l =<$fh>)) {
	if ($l =~ m/\$VERSION\s*\=\s*([\d.]+)/) {
	    $o->{version} = $1;
	    $ok=1;
	    last;
	}
    }
    croak "Couldn't retrieve \$VERSION from $file" if !$ok;
}

sub x {
    my ($o, @cmd) = @_;
    confess '$o->x(@cmd)' if !ref $o;

    if ($cmd[0] eq 'rm') {
	shift @cmd;
	if ($o->{nop}) {
	    for (@cmd) { print "rm -rf $_\n" if -e $_; }
	} else {
	    rmtree(\@cmd, $o->{verbose});
	}

    } elsif ($cmd[0] eq 'mkdir') {
	shift @cmd;
	if ($o->{nop}) {
	    for (@cmd) { print "mkdir -p $_\n" if -e $_; }
	} else {
	    mkpath(\@cmd, $o->{verbose});
	}

    } elsif ($cmd[0] eq 'cp') {
	die "cp f1 f2" if @cmd != 3;
	print "cp $cmd[1] $cmd[2]\n" if $o->{verbose};
	if (!$o->{nop}) {
	    copy($cmd[1], $cmd[2]) or die "copy $cmd[1] $cmd[2]: $!";
	    chmod(0777, $cmd[2]) if -x $cmd[1];  # copy doesn't do this..?
	}

    } elsif ($cmd[0] eq 'mv') {
	die "mv f1 f2" if @cmd != 3;
	print "mv $cmd[1] $cmd[2]\n" if $o->{verbose};
	if (!$o->{nop}) {
	    rename($cmd[1], $cmd[2]) or die "rename $cmd[1] $cmd[2]: $!";
	}

    } else {
	print join(" ", @cmd)."\n" if $o->{verbose};
	if (!$o->{nop}) {
	    system(@cmd);
	    my ($kill, $exit) = ($? & 255, $? >> 8);
	    if ($kill) {
		die "*** Break $kill\n";
	    }
	    if ($exit) {
		die "*** Exit $exit\n";
	    }
	}
    }
}

# should do parallel XXX
sub default_targets {
    my $o = shift;
    my @t = @_;
    $o->A('made', 'Compile and link default targets.', sub {
	$o->top_go(@t);
    });
}

sub alias {
    my ($o, %map) = @_;
    while (my ($k,$v) = each %map) { $o->{alias}{$k}=$v; }
}

sub load_argv_flags {
    my ($o) = @_;
    my %opts;
    GetOptions(\%opts, 'nop', 'silent', 'verbose') or $o->top_go('usage');
    $o->{nop} = 1 if $opts{'nop'};
    $o->{verbose} = 0 if $opts{'silent'};
    $o->{verbose}++ if $opts{'verbose'};
}

sub top_go {
    my ($o, @cmds) = @_;
    push(@cmds, 'automade') if @cmds == 0;

    for my $cmd (@cmds) {
	$cmd = $o->{'alias'}{$cmd} if defined $o->{'alias'}{$cmd};
	$o->go(0, $cmd) or do {
	    if ($cmd eq 'usage') {
		print "Usage not found!  How do you use this program?\n";
		exit;
	    }
	    print "Command '$cmd' not found.\n";
	    $o->top_go('usage');
	    exit;
	}
    }
}

package Maker::Phase;
use UNIVERSAL qw(isa);
use strict;
use Carp;
use vars qw(@ISA);

@ISA = 'Maker::Unit';

sub new {
    my $class = shift;
    my $tag;
    if ($_[0] and !ref $_[0]) { $tag = shift; }
    else { $tag = $NEXT++; }
    my @U;
    my $o = bless {
	tag=>$tag,
	units => \@U,
    }, $class;
    for (@_) { $_->parent($o); push(@U, $_); }
    $o;
}

sub a {
    my $o = shift;
    while (@_ > 0) {
	# accept (code), (tag,code), or (Maker::Unit)
	my $u;
	my $a1 = shift;
	if (!ref $a1) {
	    my $a2 = shift;
	    confess "Maker::Phase->a(...): bad args $a1 $a2" if ref $a2 ne 'CODE';
	    $u = Maker::Unit->new($a1, $a2);
	} elsif (ref $a1 eq 'CODE') {
	    $u = Maker::Unit->new($a1);
	} elsif (ref $a1 and isa($a1, 'Maker::Unit')) {
	    $u = $a1;
	} else {
	    croak 'Maker::Phase->a(...): bad args: '.$a1;
	}
#	confess "Warning: overriding tag '".$u->tag."' in phase '$o->tag'\n"
#	    if (defined $o->{units}{$u->tag});
	push(@{$o->{units}}, $u);
	$u->parent($o);
    }
    $o;
}

sub go {
    my ($o, $in, $tag) = @_;
#    warn ' 'x$in . ref($o) . ' ' . $o->tag . ':';
    $in++;
    my $hit=0;
    for (my $p=0; $p < @{$o->{units}}; $p++) {
	my $v = $o->{units}[$p];
	$hit=1 if $v->go($in+1, $tag);
	if ($v->tag eq $tag) {
	    my $done = {$v=>1};
	    for (@{$o->hit($v, $done)}, $v) { $_->run; }
	    $hit=1;
	}
    }
    $hit;
}

sub hit {
    my ($o, $below, $done) = @_;
    $done->{$o} = 1;

    my @y;
    if (!$below) {
	for (my $x=0; $x < @{$o->{units}}; $x++) {
	    my $v = $o->{units}[$x];
	    if (! $done->{$v}) {
		push(@y, @{$v->hit(undef, $done)});
	    }
	}
    }
    my @z;
    for my $u (@{$o->{up}}) {
	if (! $done->{$u}) {
	    push(@z, @{$u->hit($o, $done)});
	}
    }
    push(@z, @y);
    \@z;
}

package Maker::Target;
use vars qw(@ISA);
@ISA = 'Maker::Phase';

sub hit { [] }

package Maker::Seq;
use UNIVERSAL qw(isa);
use strict;
use Carp;

use vars qw(@ISA);
@ISA = 'Maker::Phase';

    # sequential execution
sub go {
    my ($o, $in, $tag) = @_;
#    warn ' 'x$in . ref($o) . ' ' . $o->tag . ':';
    $in++;
    for (my $p=$#{$o->{units}}; $p >= 0; $p--) {
	my $v = $o->{units}[$p];
	return 1 if $v->go($in+1, $tag);
	if ($v->tag eq $tag) {
	    my $done = {$o=>1};
	    my @z;
	    for (@{$o->{up}}) { push(@z, @{$_->hit($o, $done)}); }
	    for (my $x=0; $x <= $p; $x++) {
		push(@z, @{$o->{units}[$x]->hit(undef, $done)});
	    }
	    for (@z) { $_->run; }
	    return 1;
	}
    }
    0;
}

sub hit {
    my ($o, $below, $done) = @_;
    $done->{$o} = 1;

    my @y;
    for (my $x=0; $x < @{$o->{units}}; $x++) {
	my $v = $o->{units}[$x];
	last if ($below and $v eq $below);  # Seq - stop at hit index
	if (! $done->{$v}) {
	    push(@y, @{$v->hit(undef, $done)});
	}
    }
    my @z;
    for my $u (@{$o->{up}}) {
	if (! $done->{$u}) {
	    push(@z, @{$u->hit($o, $done)});
	}
    }
    push(@z, @y);
    \@z;
}

package Maker::Unit;
use strict;
use Carp;

sub new {
    croak "Maker::Unit->new([tag, ]code)" if @_ > 3;
    my $class = shift;
    my ($tag, $code);
    if (@_ == 1) {
	$tag = $NEXT++;
	$code = shift;
    } else {
	$tag = shift;
	$code = shift;
    }
    confess "Expecting CODE" unless ref $code eq 'CODE';
    bless {tag=>$tag, code=>$code}, $class;
}
sub a { confess }
sub tag { $_[0]->{tag}; }
sub contains { 0 }
sub parent {
    my ($o, $up) = @_;
    push(@{$o->{up}}, $up);
}
sub hit { #??
    my ($o, $below, $done) = @_;
    if (! $done->{$o}) {
	$done->{$o} = 1;
	[$o];
    } else {
	[];
    }
}
sub go {
    my ($o, $in, $tag) = @_;
#    warn ' 'x$in . "|".$o->tag . "| =? |$tag|";
    0;
}
sub run {
    my $o = shift;
#    warn "* $o->{'tag'}";
    &{$o->{code}};
}

1;
