# Copyright (c) 1997 Joshua Nathaniel Pritikin.  All rights reserved.
# This package is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.

# To add rules, just set your rules @ISA = 'Maker::Rules'.  As the rules
# mature, they can migrate into this package.

package Maker::Rules;
use strict;
use Carp;
use Cwd;
use Config;
use File::stat;
use ExtUtils::Embed;

sub new {
    croak "Maker::Rules->new(pkg[, hint])" if (@_ < 2 or @_ > 3);
    my ($class, $pkg, $hint) = @_;
    my $o = bless { pkg=>$pkg }, $class;
    $o->set_defaults($hint) if $hint;
    $o;
}

sub x { 
    my $o = shift;
    $o->{pkg}->x(@_);
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

sub set_defaults {
    my ($o, $hint) = @_;

    $o->{hint} = $hint;

    $o->exe(perl => 'perl');
    $o->exe(xsubpp => "$Config{privlibexp}/ExtUtils/xsubpp");
    $o->flags('xsubpp', "-typemap", "$Config{privlibexp}/ExtUtils/typemap");

    if ($hint eq 'perl-module') {
	$o->{install_dirs} = {
	    'bin' => ["./blib/bin", $Config{installbin}],
	    'man1' => ["./blib/man/man1", $Config{installman1dir}],
	    'man3' => ["./blib/man/man3", $Config{installman3dir}],
	    'script' => ["./blib/bin", $Config{installscript}],
	    'arch' => ["./blib/arch", $Config{installsitearch}],
	    'lib' => ["./blib/lib", $Config{installsitelib}],
	};
	$o->spotless('./blib');
    }

    # system dependent section

    if ($Config{archname} eq 'sun4-solaris') {
	# assume SunPro 4.0
	$o->exe('cxx', 'CC');
	$o->spotless('Templates.DB');

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
	} else {
	    die "unknown source type '$f'";
	}
    }
}

sub exe {
    confess '$o->exe(exe[, path])' if (@_ != 2 and @_ != 3);
    my ($o, $exe, $path) = @_;
    $o->{exe}{$exe} = $path if $path;
    if (defined $o->{exe}{$exe}) {
	$o->{exe}{$exe};
    } else {
	croak "Exe $exe unknown";
    }
}

# !flag to remove flags? XXX
sub flags {
    confess '$o->flags(exe[, -flag, ...])' if @_ < 2;
    my ($o, $exe, @add) = @_;
    push(@{$o->{flags}{$exe}}, @add) if @add > 0;
    return () if !defined $o->{flags}{$exe};
    @{$o->{flags}{$exe}};
}

sub pod2man {
    my ($o, $pod, $section) = @_;
    my $stem = $pod;
    $stem =~ s/\.[^.]+$//;
    $o->clean("$stem.$section");
    new Maker::Unit(sub {
	$o->x("pod2man $pod > $stem.$section");
    });
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
};

sub _populate_install {
    my ($o, $real, $map) = @_;
    new Maker::Unit(sub {
	my $Dest = $o->{install_dirs};
	while (my($k,$v) = each %$map) {
	    confess "Unknown dest $k" if !$Dest->{$k};
	    my ($blib,$rdir) = @{$Dest->{$k}};
	    
	    for my $f (@$v) {
		if (!$real) {
		    $o->x('cp', $f, "$blib/$f") if -e $f;
		} else {
		    $o->x('cp', "$blib/$f", "$rdir/$f");
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
    die "OS_LDBBASE not set" unless defined $ENV{OS_LDBBASE};

    $o->flags('cxx', '-vdelx', '-pta'); # fix vector delete & full tmpl instantiation
    $o->flags('cxx', "-I$ENV{OS_ROOTDIR}/include", qq(-DSCHEMADIR="$o->{osdbdir}"));
    $o->flags('ld', "-R $ENV{OS_ROOTDIR}/lib");

    my %features;
    for (@$libs) {
	croak "objstore feature '$_' unknown" if !defined $OS_FEATURE->{$_};
	$features{$_}=1;
    }
    for (qw( evolution queries mop dbutil compactor collections )) {
	if (defined $features{$_}) {
	    die $_ if !defined $OS_FEATURE->{$_};
	    $o->flags('ld', $OS_FEATURE->{$_}{lib});
	    $o->flags('LDB', "$ENV{OS_LDBBASE}/lib/".$OS_FEATURE->{$_}{ldb}) if
		defined $OS_FEATURE->{$_}{ldb};
	}
    }
    $o->flags('ld', "-los", "-losths");
    
    $o->clean("$tag-osschema.c");
    # osrm -f foo.db

    new Maker::Seq(new Maker::Unit("ossg $tag", sub {
	if (newer("$tag-osschema.c", "$tag-schema.c")) {

	    my @inc = grep(/^-I/, $o->flags('cxx'));
	    $o->x("ossg", @inc, '-asdb', "$o->{osdbdir}/$tag.adb",
		  '-assf', "$tag-osschema.c", "$tag-schema.c",
		  $o->flags('LDB'));
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

    my $xsi = 'perlxsi';
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
    new Maker::Seq("xs $f", new Maker::Unit("$f.c -> $f.xs", sub {
	if (newer("$f.c", "$f.xs", "typemap")) {
	    $o->x(join(' ', $o->exe('perl'), $o->exe('xsubpp'), '-C++', '-prototypes',
		       $o->flags('xsubpp'), "$f.xs", ">$f.tc"));
	    $o->x('mv', "$f.tc", "$f.c");
	}
    }),
		   $o->cxx("$f.c"));
}

sub link {
    my ($o, $ld, $out) = @_;

    if ($out =~ /^lib/) {
	# -G shared library
	# -pic
	die "not implemented";
    } else {
	$o->clean($out);
	new Maker::Unit(sub {
	    my $ld = $o->exe($ld);
	    $o->x($ld, @{$o->{'src'}{o}}, "-o", $out, $o->flags('ld'));
	});
    }
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
	$^X = $perl ? $perl : $o->exe('perl');
	my @tests = grep(!/\~$/, sort glob('t/*'));
	if ($o->nop) {
	    for (@tests) { print "$^X -Mblib $_\n"; }
	} else {
	  Test::Harness::runtests(@tests);
	}
    });
}

1;

