use lib './lib';
use ObjStore::Config ':ALL';
use ExtUtils::MakeMaker;

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

sub MY::postamble {
    my $sver = '09';
    '
osperl-'.$sver.'-osschema.c :: osperl-'.$sver.'-schema.cc $(H_FILES)
	ossg -DOSSG=1 $(INC) $(DEFINE_VERSION) $(XS_DEFINE_VERSION) \
	  -I$(PERL_INC) $(DEFINE) -showw -nout neutral-osperl \
	  -asdb '.$sdir.'/osperl-'.$sver.'.adb \
	  -assf osperl-'.$sver.'-osschema.c \
	  osperl-'.$sver.'-schema.cc $(OS_LIBDIR)/liboscol.ldb

clean ::
	-rm -f osperl-'.$sver.'-osschema.c neutral-osperl dextv*[ch]

#all :: pm_to_blib
#	cp ./PoweredByOS.gif $(INST_LIB)/ObjStore/PoweredByOS.gif

dextv.c dextv.h dextvpriv.h dextvpub.h :: dextv.tmpl
	tvgen.pl -p dex

osperl.h :: dextv.h

';
}

sub MY::xs_o {''}  #try to keep .xs.o files from rebuilding!
sub MY::makefile {''} # driving me crazy!

#$Verbose = 1;
WriteMakefile
    (
     NAME         => 'ObjStore',
     PREREQ_PM	  => { Tree::Fat => 0.04 },
     VERSION_FROM => 'lib/ObjStore.pm',
#     OPTIMIZE     => '-g',
     'EXE_FILES'  => [qw/ospeek posh osp_hack/],
     'LIBS'     => ["-L$ENV{OS_ROOTDIR}/lib -loscol -los -losths"],
     'DEFINE'   => "-DOSP_DEBUG -DDEBUGGING -DSCHEMADIR=$sdir -DHIDEMYMALLOC",
     'INC'      => "-I$OS_ROOTDIR/include",
     'OBJECT'	=> join(' ',reverse qw[osperl-09-osschema.o txn.o ObjStore.o
				       osperl.o GENERIC.o dextv.o FatTree.o]),
     'XSPROTOARG' => '-prototypes -nolinenumbers',
     dist	=> {COMPRESS=>'gzip -9f', SUFFIX => 'gz'},
    );

__END__;
