#!./perl -w

use strict;
use lib './lib';
use ExtUtils::MakeMaker;
use ObjStore::MakeMaker ':ALL';

print "
*** Be sure to read the ./INSTALL file first!  The usual make, ***
*** test, and install steps are not sufficient!                ***

Edit ./lib/ObjStore/Config.pm to change the following:
  SCHEMA_DBDIR = ".$ObjStore::Config::SCHEMA_DBDIR."
  TMP_DBDIR    = ".$ObjStore::Config::TMP_DBDIR."

";

#$Verbose = 1;
WriteMakefile
    (
     NAME         => 'ObjStore',
     PREREQ_PM	  => { 'Tree::Fat' => 1.03, Test => 1.03,
		       # Proc::Daemon?
		     },
#     OPTIMIZE => '-g',
     LINKTYPE => 'dynamic',  # static not supported!!!
     VERSION_FROM => './lib/ObjStore.pm',
     EXE_FILES  => [qw/ospeek posh osperlserver qtposh/],
     dist	=> {COMPRESS=>'gzip -9f', SUFFIX => 'gz'},
    );

sub MY::linkext { 
    'linkext::
	@$(NOOP)

'
}
