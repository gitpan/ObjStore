#!./perl -w

use strict;
use lib './lib';
use ObjStore::Config ':ALL';
use ExtUtils::MakeMaker;
use vars qw(@PREREQ);

if ($] < 5.00404) {
    print "perl 5.004_04 (or better) is required\n";
    exit;
}

print "\nPlease edit lib/ObjStore/Config.pm to change the following parameters:\n";
print "  SCHEMA_DBDIR = ".&SCHEMA_DBDIR."\n";
print "  TMP_DBDIR    = ".&TMP_DBDIR."\n";
print "\n";

# Also see the ./hints directory!

my $OS_ROOTDIR = $ENV{OS_ROOTDIR} or
    die "Please set OS_ROOTDIR to the top of the ObjectStore distribution!\n";

my $OS_LIBDIR = $ENV{OS_LIBDIR} or "$ENV{OS_ROOTDIR}/lib";

my $sdir = &SCHEMA_DBDIR;

my $schema_version = '10';

sub MY::postamble {
    my $sver = $schema_version;
    '
osperl-'.$sver.'-osschema.c :: osperl-'.$sver.'-schema.cc $(H_FILES)
	ossg -DOSSG=1 $(INC) $(DEFINE_VERSION) $(XS_DEFINE_VERSION) \
	  -I$(PERL_INC) $(DEFINE) -showw -nout neutral-osperl \
	  -asdb '.$sdir.'/osperl-'.$sver.'.adb \
	  -assf osperl-'.$sver.'-osschema.c \
	  osperl-'.$sver.'-schema.cc $(OS_LIBDIR)/liboscol.ldb

clean ::
	-rm -f osperl-'.$sver.'-osschema.c neutral-osperl dextv*[ch]
	-rm -f CCov/* ccov_registry.* .ccov-timestamp

#all :: pm_to_blib
#	cp ./PoweredByOS.gif $(INST_LIB)/ObjStore/PoweredByOS.gif

dextv.c dextv.h dextvpriv.h dextvpub.h :: dextv.tmpl
	tvgen.pl -p dex

osperl.h :: dextv.h

';
}

my $ccov=0;
push(@PREREQ, 'Devel::CCov' => 0.06) if $ccov;
my @CCOV = $ccov? 'ccov_registry.o':'';

sub MY::c_o {
    if ($ccov) {
	my @rules = split(m/( \. \w+ \$\(OBJ_EXT\) \: )/x,
			  shift->MY::SUPER::c_o(@_));
	shift @rules if $rules[0] !~ m/^\./;
	for (my $r=0; $r < @rules; $r += 2) {
	    if ($rules[$r] =~ m/^ \. (\w+) \$ /x) {
		my $prefix = $1;
		$rules[$r+1] =~ s{\$\*\.$prefix}{CCov/\$*.$prefix};
		my $CCOV = ('	@test -d CCov || mkdir CCov'."\n".
			    '	ccovinstrument -c $*.'.$prefix.' -o CCov/$*.'.$prefix.' -e CCov/$*.err'."\n");
		$rules[$r+1] =~ s/\n/\n$CCOV/;
	    }
	}
	push(@rules, '
ccov_registry$(OBJ_EXT): .ccov-timestamp
	ccovinstrument -r
	$(CCCMD) $(CCCDLFLAGS) $*.c
');
	join('', @rules);
    } else {
	shift->MY::SUPER::c_o(@_)
    }
}

#$Verbose = 1;
WriteMakefile
    (
     NAME         => 'ObjStore',
     PREREQ_PM	  => { 'Tree::Fat' => 0.04, Test => 0.02, @PREREQ },
     VERSION_FROM => 'lib/ObjStore.pm',
#     OPTIMIZE     => '-g',
     EXE_FILES  => [qw/ospeek posh osp_hack/],
     'LIBS'     => ["-L$ENV{OS_ROOTDIR}/lib -loscol -los -losths"],
     'DEFINE'   => "-DOSP_DEBUG -DDEBUGGING -DSCHEMADIR=$sdir -DHIDEMYMALLOC",
     INC      => "-I. -I$OS_ROOTDIR/include",
     'OBJECT'	=> join(' ',reverse
			"osperl-$schema_version-osschema.o", @CCOV,
			qw[txn.o ObjStore.o osperl.o GENERIC.o dextv.o
			   FatTree.o osp_hkey.o ODI.o Splash.o]),
     'XSPROTOARG' => '-prototypes -nolinenumbers',
     dist	=> {COMPRESS=>'gzip -9f', SUFFIX => 'gz'},
    );

package MY;

sub xs_o {''}  #try to keep .xs.o files from rebuilding!
sub makefile {''} # driving me crazy!

__END__
