# Copyright (c) 1997 Joshua Nathaniel Pritikin.  All rights reserved.
# This package is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.

# To add rules, just set your rules @ISA = 'Maker::Rules'.  As the rules
# mature, they can migrate into this package.

package Maker::Rules;
use strict;
require Exporter;
use vars qw(@ISA @EXPORT);
@ISA    = qw(Exporter);
@EXPORT = qw(&newer);

require Maker::Package;
use Carp;
use Cwd;
use Config;
use IO::File;
use File::stat;
use ExtUtils::Embed;

sub new {
    croak "Maker::Rules->new(pkg[, hint])" if (@_ < 2 or @_ > 3);
    my ($class, $pkg, $hint) = @_;
    my $o = bless { pkg=>$pkg }, $class;
    $o->set_defaults($hint);
    $o;
}

sub x { 
    my $o = shift;
    $o->{pkg}->x(@_);
}

sub z { 
    my $o = shift;
    $o->{pkg}->z(@_);
}

sub clean {
    my $o = shift;
    $o->{pkg}->clean(@_);
}

sub spotless {
    my $o = shift;
    $o->{pkg}->spotless(@_);
}

# inherit from Maker::Package
for my $k (qw(nop verbose version)) {
    eval "sub $k { \$_[0]->{pkg}{$k} }";
    die $@ if $@;
}

sub set_install_dirs {
    my ($o, $map) = @_;
    $o->{install_dirs} = $map;
}

sub want_threads {
    my ($o) = @_;
    $o->{thread};
}

sub set_defaults {
    my ($o, $hint) = @_;

    $o->{hint} = $hint;

    $o->flags('cc-dl', $Config{cccdlflags});
    $o->flags('ld-dl', $Config{lddlflags});

    $o->exe(perl => "$Config{bin}/perl");

    if ($hint and $hint eq 'perl-module') {
	$o->flags('cc', $Config{'ccflags'});
	$o->flags('cxx', $Config{'ccflags'});
	$o->exe(xsubpp => "$Config{privlibexp}/ExtUtils/xsubpp");
	$o->flags('xsubpp', "-typemap", "$Config{privlibexp}/ExtUtils/typemap");

	$o->set_install_dirs({
	    'bin' => ["./blib/bin", $Config{installbin}, $Config{bin}],
	    'man1' => ["./blib/man/man1", $Config{installman1dir}],
	    'man3' => ["./blib/man/man3", $Config{installman3dir}],
	    'script' => ["./blib/bin", $Config{installscript}, $Config{script}],
	    'arch' => ["./blib/arch", $Config{installsitearch}],
	    'lib' => ["./blib/lib", $Config{installsitelib}],
	});
	$o->spotless('./blib');
    }

    # system dependent section

    if ($Config{archname} =~ m/^sun4-solaris(.*)$/) {
	$o->{thread} = ($1 =~ /thread/);

	# assume SunPro 4.0
	$o->exe('cxx', 'CC');
	$o->flags('cxx-dl', '-KPIC', '-G');
	$o->spotless('Templates.DB');
	if ($o->want_threads) {
	    $o->flags('cxx', '-mt');
	    $o->flags('ld', '-mt');
	}

	# special phase
	push(@{$o->{postlink}}, sub {  
	    my ($o) = @_;
	    $o->x('rm', 'ir.out');  # tmp file created by the linker??
	});
    }
}

sub src {
    my $o=shift;
    for my $f (@_) {
	if ($f =~ /\.o$/) {
	    push(@{$o->{src}{o}}, $f);
	} elsif ($f =~ /\.a$/) {
	    push(@{$o->{src}{a}}, $f);
	} else {
	    die "unknown source type '$f'";
	}
    }
}

sub get_src {
    my $o = shift;
    my @z;
    for (@_) {
	my $a = $o->{'src'}{$_};
	push(@z, @$a) if $a;
    }
    @z;
}

sub exe {
    confess '$o->exe(exe[, path])' if (@_ != 2 and @_ != 3);
    my ($o, $exe, $path) = @_;
    $o->{exe}{$exe} = $path if $path;
    if (defined $o->{exe}{$exe}) {
	$o->{exe}{$exe};
    } else {
	undef;
    }
}

# !flag to remove flags? XXX
sub flags {
    confess '$o->flags(exe[, -flag, ...])' if @_ < 2;
    my ($o, $exe, @add) = @_;
    # optimize XXX
  ADD: for my $new (@add) {
      for (@{$o->{flags}{$exe}}) { last ADD if $_ eq $new; }
      push(@{$o->{flags}{$exe}}, $new);
    }
    return () if !defined $o->{flags}{$exe};
    @{$o->{flags}{$exe}};
}

sub pod2man {
    my ($o, $pod, $section) = @_;
    my $stem = $pod;
    $stem =~ s/\.[^.]+$//;
    $o->clean("$stem.$section");
    new Maker::Unit("$stem.$section", sub {
	if (newer("$stem.$section", $pod)) {
	    $o->x("pod2man $pod > $stem.$section");
	}
    });
}

sub pod2html {
    my $o = shift @_;
    my @r;
    for my $pod (@_) {
	my $stem = $pod;
	$stem =~ s/\.[^.]+$//;
	$o->clean("$stem.html");
	push(@r, new Maker::Unit("$stem.html", sub {
	    if (newer("$stem.html", $pod)) {
		$o->x("pod2html $pod > $stem.html");
	    }
	}));
    }
    $o->spotless("pod2html-dircache", "pod2html-itemcache");
    if (@r == 1) {
	@r;
    } else {
	new Maker::Phase(@r);
    }
}

sub _make_install_dirs {
    my ($o, $real, $map) = @_;
    new Maker::Unit(sub {
	my @ds;
	my $Dest = $o->{install_dirs};
	if (!$real) {
	    while (my($k,$v) = each %$Dest) { push(@ds, $v->[0]); }
	} else {
	    while (my($k,$v) = each %$map) { push(@ds, $Dest->{$k}[1]); }
	}
	$o->x('mkdir', @ds);
    });
}

sub _populate_install {
    croak "_populate_install(o,real,map)" if @_ != 3;
    my ($o, $real, $map) = @_;
    new Maker::Unit(sub {
	my $Dest = $o->{install_dirs};
	while (my($k,$v) = each %$map) {
	    confess "Unknown dest $k" if !$Dest->{$k};
	    my ($blib,$rdir) = @{$Dest->{$k}};
	    
	    for my $f (@$v) {
		if ($f =~ m|/$|) {
		    if (!$real) {
			$o->x('mkdir', "$blib/$f");
		    } else {
			$o->x('mkdir', "$rdir/$f");
		    }
		} else {
		    if (!$real) {
			my $base = $f;
			$base =~ s|^.*/||;
			if (-e $f and newer("$blib/$f", $f)) {
			    $o->x('cp', $f, "$blib/$f");
			} elsif (-e $base and newer("$blib/$f", $base)) {
			    $o->x('cp', $base, "$blib/$f");
			}
		    } else {
			if (-e "$blib/$f") {
			    if (newer("$rdir/$f", "$blib/$f")) {
				$o->x('cp', "$blib/$f", "$rdir/$f");
			    }
			} elsif (-e $f) {
			    if (newer("$rdir/$f", $f)) {
				$o->x('cp', $f, "$rdir/$f");
			    }
			} else {
			    confess "$f missing";
			}
		    }
		}
	    }
	}
    });
}

sub blib {
    my ($o, $map) = @_;
    $o->_make_install_dirs(0, $map);
}

sub populate_blib {
    my ($o, $map) = @_;
    $o->_populate_install(0, $map);
}

sub install {
    my ($o, $map) = @_;
    if ($map->{bin} and defined $o->{install_dirs}{bin}[2]) {
	for my $b (@{$map->{bin}}) {
	    $o->exe($b, "$o->{install_dirs}{bin}[2]/$b") if !$o->exe($b);
	}
    }
    new Maker::Seq($o->_make_install_dirs(1, $map),
		   $o->_populate_install(1, $map),
		   new Maker::Unit('_inst', sub {}));
}

sub uninstall {  # merge with install XXX
    my ($o, $map) = @_;
    new Maker::Unit('_uninst', sub {
	my $Dest = $o->{install_dirs};
	while (my($k,$v) = each %$map) {
	    my $rdir = $Dest->{$k}[1];
	    for my $f (@$v) { $o->x('rm', "$rdir/$f"); }
	}
    });
}

# make more compiler neutral XXX
sub opt {
    my ($o, $opt) = @_;
    if ($opt) {
	# -DNDEBUG to turn off assert
	$o->flags('cc', '-O');
	$o->flags('cxx', '-O');
    } else {
	$o->flags('cc', '-g');
	$o->flags('cxx', '-g');
    }
}

my $OS_FEATURE = {
    'collections' => { ldb => 'liboscol.ldb', lib => '-loscol' },
    'compactor' => { ldb => 'liboscmp.ldb', lib => '-loscmp' },
    'queries' => { ldb => 'libosqry.ldb', lib => '-losqry' },
    'evolution' => { ldb => 'libosse.ldb', lib => '-losse' },
    'mop' => { lib => '-losmop' },
    'dbutil' => { lib => '-losdbu' },
};    

sub objstore {
    my ($o,$schdir,$tag,$libs) = @_;
    $o->{osdbdir} = $schdir;

    die "OS_ROOTDIR not set" unless defined $ENV{OS_ROOTDIR};
    $ENV{OS_LIBDIR} = "$ENV{OS_ROOTDIR}/lib" if !defined $ENV{OS_LIBDIR};

    $o->flags('cxx', '-vdelx', '-pta'); # fix vector delete & full tmpl instantiation
    $o->flags('cxx', "-I$ENV{OS_ROOTDIR}/include", qq(-DSCHEMADIR="$o->{osdbdir}"));
    $o->flags('ld', "-R$ENV{OS_ROOTDIR}/lib");
#    $o->flags('ld', "-L$ENV{OS_ROOTDIR}/lib");

    my %features;
    for (@$libs) {
	croak "objstore feature '$_' unknown" if !defined $OS_FEATURE->{$_};
	$features{$_}=1;
    }
    for (qw( evolution queries mop dbutil compactor collections )) {
	if (defined $features{$_}) {
	    die $_ if !defined $OS_FEATURE->{$_};
	    $o->flags('ld', $OS_FEATURE->{$_}{lib});
	    $o->flags('LDB', "$ENV{OS_LIBDIR}/".$OS_FEATURE->{$_}{ldb}) if
		defined $OS_FEATURE->{$_}{ldb};
	}
    }
    $o->flags('ld', "-los",
	      $o->want_threads? "-losthr" : "-losths",
	      $Config{libs});  # -lC is not be required on solaris
    
    $o->clean("$tag-osschema.c", "neutral-$tag");
#    $o->spotless(sub {$o->x("osrm -f $o->{osdbdir}/$tag.adb");});

    new Maker::Seq(new Maker::Unit("ossg $tag", sub {
	my $adb = "$o->{osdbdir}/$tag.adb";
	if ($o->z("ostest", "-s", $adb) or
	    newer("$tag-osschema.c", "$tag-schema.c")) {
	    
	    my @inc = grep(/^-I/, $o->flags('cxx'));
	    $o->x("ossg", @inc, '-DOSSG=1', '-showw', '-nout', "neutral-$tag",
		  '-asdb', $adb, '-assf', "$tag-osschema.c",
		  "$tag-schema.c", $o->flags('ossg'), $o->flags('LDB'));
	}
     }),
		   $o->cxx("$tag-osschema.c"));
}

# check dependencies XXX
sub cxx {
    my $o = shift;
    my @u;
    my $cxx = $o->exe('cxx');
    for my $file (@_) {
	my $f = $file;
	my $obj = $file;
	$obj =~ s/\.[^.]+$/.o/;
	$o->clean($obj);
	push(@u, new Maker::Unit($obj, sub {
	    if (newer($obj, $f)) {
		$o->x($cxx, $o->flags('cxx'), "-c", $f);
	    }
	    $o->src($obj);
	}));
    }
    if (@u == 1) {
	@u;
    } else {
	new Maker::Phase(@u);
    }
}

sub embed_perl {
    my ($o, @mod) = @_;

    my $xsi = 'perlxsi-'.join('', map { substr($_, 0, 3) } @mod);
    $o->clean("$xsi.o");

    $o->flags('cxx', "-I$Config{archlibexp}/CORE");
    $o->flags('ld', split(/\s+/, ldopts(0,\@mod,[],'')));

    new Maker::Unit(sub {
	unshift(@mod, 'DynaLoader');
	if (!-e "$xsi.o") {
	    xsinit("$xsi.c", 0, \@mod);

	    # factor out into separate sub
	    $o->x($Config{cc}, $o->flags('cc'), $Config{'ccflags'},
		  "-I$Config{archlibexp}/CORE", '-c', "$xsi.c");
	    $o->x('rm', "$xsi.c");
	}
	$o->src("$xsi.o");
    });
}

sub xs {
    confess '$o->xs(file.xs)' if @_ != 2;
    my ($o, $f) = @_;
    $f =~ s/\.xs$//;
    $o->clean("$f.c");
    $o->flags('cxx', "-I$Config{archlibexp}/CORE");
    my $ver = $o->version;
    $o->flags('cxx', "-DXS_VERSION=\"$ver\"");
    new Maker::Seq("xs $f", new Maker::Unit("$f.c -> $f.xs", sub {
	if (newer("$f.c", "$f.xs", "typemap")) {
	    $o->x(join(' ', $o->exe('perl'), $o->exe('xsubpp'), '-C++', '-prototypes',
		       $o->flags('xsubpp'), "$f.xs", ">$f.tc"));
	    $o->x('mv', "$f.tc", "$f.c");
	}
    }),
		   $o->cxx("$f.c"));
}

sub HashBang {
    my $o = shift;
    my $ename = shift;
    my @REST = @_;
    new Maker::Unit(sub {
	my $exe = $o->exe($ename);
	my ($s,$d) = (new IO::File, new IO::File);
	for my $bin (@REST) {
	    {
		$s->open($bin) or croak "$bin not found";
		my $l1 = <$s>;
		my $args;
		if ($l1 =~ /^\#\!\S+\s(.*)$/) {
		    $args = $1;
		} else {
		    croak "$bin doesn't start with \#!";
		}
		$d->open(">$bin.new") or croak "open $bin.new: $!";
		print $d "#!$exe $args\n";
		while (defined(my $l=<$s>)) {
		    print $d $l;
		}
		$s->close;
		$d->close;
	    }
	    rename("$bin.new", $bin) or croak "rename $bin.new $bin: $!";
	    chmod(oct('777'), $bin) or croak "chmod 777 $bin: $!";
	}
    });
}

sub dlink {
    my ($o, $ldname, $out) = @_;

    $o->flags('cc', $o->flags('cc-dl'));
    $o->flags('cxx', $o->flags('cxx-dl'));
    new Maker::Unit(sub {
	my $ld = $o->exe($ldname);
	my $dir = $out;
	$dir =~ s|\/[^/]*$||;
	$o->x('mkdir', $dir);
	my @src = $o->get_src('o','a');
	if (newer($out, @src)) {
	    $o->x($ld, $o->flags('ld-dl'), @src, "-o", $out, $o->flags('ld'));
	    $o->x('chmod', 0755, $out);
	}
    });
}

sub link {
    my ($o, $ld, $out) = @_;
    my $name = $out;
    $name =~ s|^.*/([^/]+)$|$1|;
    $o->exe($name, $out);
    $o->clean($out);
    new Maker::Unit(sub {
	my $ld = $o->exe($ld);
	my @src = $o->get_src('o','a');
	if (newer($out, @src)) {
	    $o->x($ld, @src, "-o", $out, $o->flags('ld'));
	}
    });
}

# cache stat results XXX
# use makedepend & SDBM (?)
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

require Test::Harness;
sub test_harness {
    my ($o, $perl) = @_;
    new Maker::Unit('_test', sub {
	if (!$perl) { $perl = $o->exe('perl'); }
	else { $perl = $o->exe($perl); }
	my $map = $o->{install_dirs};
	print "PERL_DL_NONLAZY=1\n";
	$ENV{PERL_DL_NONLAZY}=1;
#	$ENV{PERL_DL_DEBUG}=1;
	$o->z($perl, "-I$map->{arch}[0]", "-I$map->{lib}[0]", "-I$Config{archlib}",
	      "-I$Config{privlib}", "-e",
	      'use Test::Harness qw(&runtests $verbose); $verbose=0; runtests @ARGV;',
	      grep(!/\~$/, sort glob('t/*.t')));

    });
}

1;

