#!./perl -w
use strict;
use ExtUtils::MakeMaker;
use lib ('../../lib','.');
use ObjStore::MakeMaker qw(add_os_args);

my $v = '01';
sub MY::postamble {
    os_schema_rule("REP-FatTree-$v.sch").
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

WriteMakefile(add_os_args(NAME => 'ObjStore::REP::FatTree',
			  OBJECT => join(' ',qw[FatTree.o dex2tv.o avtv.o
						tvcommon.o],
					 "REP-FatTree-$v.o")));
