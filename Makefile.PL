#!./perl -w

use strict;
use lib './lib';
use ObjStore::Config ':ALL';
use ExtUtils::MakeMaker;

print "
Please edit lib/ObjStore/Config.pm to change the following parameters:
  SCHEMA_DBDIR = ".&SCHEMA_DBDIR."
  TMP_DBDIR    = ".&TMP_DBDIR."

";

my $v = $OSPERL_SCHEMA_VERSION;
my %mk = os_stdargs("ObjStore", ['-loscol']);

#$Verbose = 1;
WriteMakefile
    (%mk,
     PREREQ_PM	  => { 'Tree::Fat' => 1.03, Test => 1.03,
		       # Proc::Daemon?
		     },
     OBJECT => join(' ', qw[osperl.o txn.o ObjStore.o FatTree.o ODI.o Splash.o
			   avtv.o dex2tv.o osp_hkey.o tvcommon.o osperl-12.o]),
#     OPTIMIZE => '-g',
     LINKTYPE => 'dynamic',  # static not supported!!!
     VERSION_FROM => './lib/ObjStore.pm',
     EXE_FILES  => [qw/ospeek posh qtposh osperlserver osp_hack/],
     dist	=> {COMPRESS=>'gzip -9f', SUFFIX => 'gz'},
    );

sub MY::postamble {
    os_schema_rule("osperl-$v.sch")
	.
	    '
dex2tv.c dex2tv.h dex2tvpriv.h dex2tvpub.h :: dex2tv.tmpl
	tvgen.pl -p dex2

tvcommon.c avtv.c avtv.h avtvpriv.h avtvpub.h :: avtv.tmpl
	tvgen.pl -p av

FatTree.h :: dex2tv.h avtv.h

clean ::
	-rm -f avtv*[ch] dex2tv*[ch] tvcommon.*
'
 }
