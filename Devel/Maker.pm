# Copyright (c) 1997 Joshua Nathaniel Pritikin.  All rights reserved.
# This package is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.

# MakeMaker.pm =~ s/^Make//;

# Why does MakeMaker make use of standard unix make when it could use
# perl exclusively?  Does make actually add much value?  I hate the syntax too.

# This should probably be redesigned to be completely generic and
# integrated with MakeMaker.

# Make compile steps more order independent

# Do recursive directories!

# Try to keep track of where we are in the build process to give good
# error messages ?

# make compile flags persistent (in AnyDBM?) so we can /depend/ on them
# generate and use c file dependencies (makedepend? or custom?)
# blib

# factor out filename translation is install & uninstall

package Devel::Maker;

use strict;
use Carp;
use Config;
use Getopt::Long;
use Cwd;
use File::stat;
use File::Copy;
use File::Path;
use Test::Harness;
use ExtUtils::Manifest qw(&mkmanifest &manicheck);
use ExtUtils::Embed;
use vars qw($CMDS $Dest);

$CMDS = [qw(help automake manifest check make test install uninstall clean dist)];

$Dest = {
    'bin' => ["./blib/bin", $Config{installbin}],
    'man1' => ["./blib/man/man1", $Config{installman1dir}],
    'man3' => ["./blib/lib/perl5/man/man3",  $Config{installman3dir}],
    'script' => ["./blib/bin", $Config{installscript}],
    'sitearch' => ["./blib/lib/perl5/site_perl/$Config{archname}",
		   $Config{installsitearch}],
    'sitelib' => ["./blib/lib/perl5/site_perl", $Config{installsitelib}],
};

sub new {
    my ($class, $conf) = @_;
    my $o = bless {}, $class;
    $o->set_defaults;
    $o->configure($conf);
    $o;
}

sub exe {
    confess '$o->exe(exe[, path])' if (@_ != 2 and @_ != 3);
    my ($o, $exe, $path) = @_;
    $o->{exe}{$exe} = $path if $path;
    $o->{exe}{$exe};
}

sub flags {
    my ($o, $exe, @add) = @_;
    push(@{$o->{flags}{$exe}}, @add) if @add > 0;
    @{$o->{flags}{$exe}};
}

# factor this out into 'PerlShell.pm' ?
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

    } elsif ($cmd[0] eq 'cp') {
	die "cp f1 f2" if @cmd != 3;
	print "cp $cmd[1] $cmd[2]\n" if $o->{verbose};
	if (!$o->{nop}) {
	    copy($cmd[1], $cmd[2]) or die "copy $cmd[1] $cmd[2]: $!";
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
		print "*** Break $kill\n";
		exit;
	    }
	    if ($exit) {
		print "*** Exit $exit\n";
		exit;
	    }
	}
    }
}

sub xsh {
    my $o = shift;
    confess 'xsh($o, @cmd)' if !ref $o;
    $o->x(join(" ", @_));
}

sub configure {
    my ($o, $params) = @_;
    
    while (my($k,$v) = each %$params) {
	if ($k eq 'name') {
	    $o->{name} = $v;
	} elsif ($k eq 'optimize') {
	    $o->{optimize} = $v;
	} elsif ($k eq 'build') {
	    $o->{build} = $v;
	} elsif ($k eq 'test_bin') {
	    $o->{test_bin} = $v;
	} elsif ($k eq 'install_map') {
	    $o->{install_map} = $v;
	} elsif ($k eq 'clean') {
	    push(@{$o->{clean}}, @$v);
	} else {
	    die "unknown config var $k";
	}
    }
}

sub set_defaults {
    my ($o) = @_;

    $o->{nop} = 0;
    $o->{verbose} = 1;   # higher values imply debugging
    $o->{name} = '?';
    $o->{version} = '?.?';

    $o->{postlink} = [];

    $o->{clean} = [qw(core blib *.o *~ .nfs*)];

    # XXX be more clever about finding xsubpp & perl
    $o->exe(perl => 'perl');
    $o->exe(xsubpp => "$Config{privlibexp}/ExtUtils/xsubpp");
    $o->flags('xsubpp', "-typemap", "$Config{privlibexp}/ExtUtils/typemap");

    $o->{src} = {   # object files ready for linking
	'c' => [],
	'cxx' => [],
	};

    # system dependent section

    if ($Config{archname} eq 'sun4-solaris') {
	# assume SunPro 4.0
	$o->exe('cxx', 'CC');
	$o->flags('cxx', '-pta');
	push(@{$o->{clean}}, 'Templates.DB');
	push(@{$o->{postlink}}, sub {
	    my ($o) = @_;
	    $o->x('rm', 'ir.out');  # tmp file created by the linker??
	});
    }
}

# XXX cache stat results
sub newer {
    my ($target, @deps) = @_;
    return 1 if !-e $target;
    my $ttm = stat($target)->mtime;
    for (@deps) {
	my $o = stat($_);
	return 1 if ($o and $o->mtime > $ttm);
    }
    0;
}

# make more compiler neutral XXX
sub opt {
    my ($o, $opt) = @_;
    if ($opt) {
	$o->flags('cc', '-O');
	$o->flags('cxx', '-O');
    } else {
	$o->flags('cc', '-g');
	$o->flags('cxx', '-g');
    }
}

sub src {
    my $o=shift;
    my $f;
    for $f (@_) {
	if ($f =~ /\.o$/) {
	    push(@{$o->{src}{o}}, $f);
	} else {
	    die "unknown source type '$f'";
	}
    }
}

sub objstore {
    my $OS_FEATURE = {
	'collections' => { ldb => 'liboscol.ldb', lib => '-loscol' },
	'compactor' => { ldb => 'liboscmp.ldb', lib => '-loscmp' },
	'queries' => { ldb => 'libosqry.ldb', lib => '-losqry' },
	'evolution' => { ldb => 'libosse.ldb', lib => '-losse' }
    };    

    my ($o,$schdir,$tag,$libs) = @_;
    $o->{osdbdir} = $schdir;

    die "OS_ROOTDIR not set" unless defined $ENV{OS_ROOTDIR};
    die "OS_LDBBASE not set" unless defined $ENV{OS_LDBBASE};

    $o->flags('cxx', '-vdelx'); # fix vector delete
    $o->flags('cxx', "-I$ENV{OS_ROOTDIR}/include", qq(-DSCHEMADIR="$o->{osdbdir}"));
    $o->flags('ld', "-R $ENV{OS_ROOTDIR}/lib");

    my %features;
    for (@$libs) { $features{$_}=1; }
    for (qw( evolution queries compactor collections )) {
	if (defined $features{$_}) {
	    die $_ if !defined $OS_FEATURE->{$_};
	    $o->flags('ld', $OS_FEATURE->{$_}{lib});
	    $o->flags('LDB', "$ENV{OS_LDBBASE}/lib/".$OS_FEATURE->{$_}{ldb});
	}
    }
    $o->flags('ld', "-los", "-losths");

    my @inc = grep(/^-I/, $o->flags('cxx'));
    $o->x("ossg", @inc, '-asdb', "$o->{osdbdir}/$tag.adb",
	  '-assf', "$tag-osschema.c", "$tag-schema.c", $o->flags('LDB'));
    $o->cxx("$tag-osschema.c");
    push(@{$o->{postlink}}, sub {
	my ($o,$out) = @_;
	$o->x("os_postlink $out");
    });
}

# check dependencies XXX
sub cxx {
    confess '$o->cxx(file.cc)' if @_ != 2;
    my ($o, $file)= @_;
    my $cxx = $o->exe('cxx');
    $o->x($cxx, $o->flags('cxx'), "-c", $file);
    $file =~ s/\.[^.]+$/.o/;
    $o->src($file);
}
 
sub embed_perl {
    my ($o, @mod) = @_;
    my $xsi = 'perlxsi';
    unshift(@mod, 'DynaLoader');
    if (!-e "$xsi.o") {
	xsinit("$xsi.c", 0, \@mod);
	# factor out into separate sub
	$o->x($Config{cc}, $o->flags('cc'), $Config{'ccflags'},
	      "-I$Config{archlibexp}/CORE", '-c', "$xsi.c");
	$o->x('rm', "$xsi.c");
    }
    $o->src("$xsi.o");
    $o->flags('cxx', "-I$Config{archlibexp}/CORE");
    $o->flags('ld', split(/\s+/, ldopts(0,\@mod,[],'')));
}

sub xs {
    confess '$o->xs(file.xs)' if @_ != 2;
    my ($o, $f) = @_;
    $f =~ s/\.xs$//;
    if (newer("$f.o", "$f.xs", "typemap")) {
	$o->xsh($o->exe('perl'), $o->exe('xsubpp'), '-C++', '-prototypes',
		$o->flags('xsubpp'), "$f.xs", ">$f.tc");
	$o->x('mv', "$f.tc", "$f.c");
	$o->cxx("$f.c");
    } else {
	$o->src("$f.o");
    }
}

sub link {
    my ($o, $ld, $out) = @_;

    if ($out =~ /^lib/) {
	# not implemented
	# -G shared library
	# -pic
    } else {
	my $ld = $o->exe($ld);
	$o->x($ld, @{$o->{'src'}{o}}, "-o", $out, $o->flags('ld'));
	for (@{$o->{postlink}}) { &$_($o, $out); }
    }
}

sub op_test {
    my ($o) = @_;
#    system("./osperl t/basic.t");
#    system("./osperl t/cursor.t");
#    system("./osperl t/hash.t");
#    system("./osperl t/segment.t");
    $^X = $o->{test_bin}? $o->{test_bin} : $o->exe('perl');
    my @tests = grep(!/\~$/, sort glob('t/*'));
    if ($o->{nop}) {
	for (@tests) { print "$^X $_\n"; }
    } else {
	runtests(@tests);
    }
}

sub mk_installdirs {
    my ($o, $real) = @_;
    my $what = $o->{install_map};
    while (my($k,$v) = each %$what) {
	confess "Unknown dest $k" if !$Dest->{$k};
	my $dir = $Dest->{$k}[$real];
	mkpath([$dir], 1);
    }
}

sub op_build {
    my ($o) = @_;
    $o->mk_installdirs(0);
    &{$o->{build}}($o);
    $o->op_install(0);
}

# not real - move from ./ to ./blib
# real     - copy from ./blib to real install area
sub op_install {
    my ($o, $real) = @_;
    $real = 1 if !defined $real;  #sloppy XXX

    $o->mk_installdirs($real) if $real;
    my $what = $o->{install_map};
    while (my($k,$v) = each %$what) {
	confess "Unknown dest $k" if !$Dest->{$k};
	my ($blib,$rdir) = @{$Dest->{$k}};

	if (!$real) {
	    for my $f (@$v) {
		if ($k eq 'man3') {
		    if ($f =~ m/^(.+)\.pm$/) {
			$o->x("pod2man $f > $blib/${1}.3");
		    } else {
			die "teach me!";
		    }
		} else {
		    $o->x('cp', $f, "$blib/$f") if -e $f;
		}
	    }
	} else {
	    for my $f (@$v) {
		if ($k eq 'man3') {
		    if ($f =~ m/^(.+)\.pm$/) {
			$o->x('cp', "$blib/${1}.3", "$rdir/${1}.3");
		    } else {
			die "teach me!";
		    }
		} else {
		    $o->x('cp', "$blib/$f", "$rdir/$f");
		}
	    }
	}
    }
    print "\nCongratulations!  $o->{name}-$o->{version} is installed.\n" if $real;
}

sub op_uninstall {
    print "As you wish...\n";
    my ($o) = @_;
    my $what = $o->{install_map};
    while (my($k,$v) = each %$what) {
	confess "Unknown dest $k" if !$Dest->{$k};
	my $rdir = $Dest->{$k}[1];
	for my $f (@$v) {
	    if ($k eq 'man3') {
		if ($f =~ m/^(.+)\.pm$/) {
		    $o->x('rm', "$rdir/${1}.3");
		} else {
		    die "teach me!";
		}
	    } else {
		$o->x('rm', "$rdir/$f");
	    }
	}
    }
}

sub op_clean {
    my ($o) = @_;
    for my $yuck (@{$o->{clean}}) { $o->x('rm', glob($yuck)); }
}

sub op_dist {
    my ($o) = @_;
    die "version missing" if !$o->{version};
    die "name missing" if !$o->{name};
    die "'./m manifest' first" if !-e './MANIFEST';
    my $dir = cwd;
    $dir =~ s|^.*/||;
    my @all = `cat ./MANIFEST`;
#    for (@all) { chop; }
    chop @all;
    my $all = join(' ', map { "$dir/$_" } @all);
    $o->x("cd ..; tar -cf - $all | gzip -c > $o->{name}-$o->{version}.tar.gz");
}

# extend to work with RCS & SCCS magic XXX
sub pm_2version {
    my ($o, $file) = @_;
    my $fh = new IO::File;
    $fh->open($file) or die "open $file: $!";
    while (defined (my $l =<$fh>)) {
	if ($l =~ m/\$VERSION\s*\=\s*['"]([\d.]+)["']/) {
	    $o->{version} = $1;
	    last;
	}
    }
    croak "Couldn't retrieve version from $file" if !$o->{version};
}

sub help {
    my ($o, $str) = @_;
    $o->{help} = $str;
}

sub op_help {
    my ($o) = @_;
    if ($o->{'help'}) {
	print $o->{'help'};
    } else {
	print "Sorry!  I am helpless.\n";
    }
}

sub enable {
    my ($o, @cmds) = @_;
    if (@cmds == 1 and $cmds[0] eq 'all') {
	@cmds = @$CMDS;
    }
    for (@cmds) { $o->{OK}{$_} = 1; }
}

sub usage {
    # do something fancy...
}

sub op_manifest {
    mkmanifest;
}

sub op_check {
    my ($o) = @_;
    print "Package $o->{name}-$o->{version} looks complete.\n" if ! manicheck;
}

sub op_automake {
    my ($o) = @_;
    $o->op_clean;
    print "Looks good.\n" if ! manicheck;
    $o->op_build;
    $o->op_test;
}

# should only be called once
sub go {
    my ($o, @ok) = @_;
    $o->enable(@ok);

    my %opts;
    GetOptions(\%opts, 'nop', 'silent', 'verbose') or $o->usage;
    $o->{nop} = 1 if $opts{'nop'};
    $o->{verbose} = 0 if $opts{'silent'};
    $o->{verbose} = 1 if $opts{'verbose'};

    my $cmd = $ARGV[0];
    $cmd = 'automake' if !$cmd;
    die "$cmd not available" if !$o->{OK}{$cmd};

    $o->opt($o->{optimize});

    no strict qw(refs);
    &{"op_$cmd"}($o);
}

1;
