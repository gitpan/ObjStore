#!/usr/local/bin/perl -w

use lib '.';
#use lib '/home/joshua/Maker-2.05';
use Config;
require Maker::Package;
require Maker::Rules;

{
    my $pk = new Maker::Package(top=>'ObjStore');
    $pk->pm_2version('ObjStore.pm');
    $pk->post_help('1. Please set the following environment variables before compiling:

OS_ROOTDIR=/nw/dist/vendor/os/4.0.2/sunpro (or whatever)
OS_LIBDIR=$OS_ROOTDIR/lib (as appropriate)
 
PATH+=$OS_ROOTDIR/bin ; LD_LIBRARY_PATH+=$OS_ROOTDIR/lib
 
2. Make sure you pick a reasonable directory for the application schema.
See $SchemaDir in ./be.

');
    
    # Specify a good directory for the application schema:
    my $SchemaDir = '/opt/os/joshua';
    
    my $linkage = 'dyn';  #'dyn' or 'static'

    $pk->default_targets('osperl', 'ospeek');

    { # osperl
	my $inst = {
	    script => [ 'ospeek' ],
	    man3 => [ 'ObjStore.3' ],
	    lib => ['ObjStore.pm', 'ObjStore/', 'ObjStore/GENERIC.pm',
		    'ObjStore/Peeker.pm', 'ObjStore/PoweredByOS.gif',
		    'ObjStore/ObjStore.html'],
	};

	if ($linkage eq 'dyn') {
	    $inst->{arch} = ['auto/ObjStore/', 'auto/ObjStore/ObjStore.so'];
	}
	else { $inst->{bin} = ['osperl']; }
	
	my $r = Maker::Rules->new($pk, 'perl-module');
	$r->opt(1);
#	$r->flags('ossg', '-padc', '-arch','set1');
	$r->flags('ld-dl', '-ztext');   # SunPro specific?
	my $build =
	    new Maker::Seq(new Maker::Phase('parallel',
					    ($linkage eq 'static' ?
					     ($r->cxx('perlmain.c'),
					      $r->embed_perl('ObjStore')) :
					     ()),
					    $r->objstore($SchemaDir, 'osperl-05',
							 ['collections']),
					    $r->cxx('osperl.c'),
					    $r->xs('GENERIC.xs'),
					    $r->xs('ObjStore.xs'),
					    ),
			   ($linkage eq 'dyn'?
			    $r->dlink('cxx', './blib/arch/auto/ObjStore/ObjStore.so') :
			    $r->link('cxx', './blib/bin/osperl')));

	$pk->a(new Maker::Seq($r->blib($inst), 
			      new Maker::Phase($build,
					       $r->pod2man('ObjStore.pod', 3),
					       $r->pod2html('ObjStore.pod')),
			      $r->populate_blib($inst),
			      new Maker::Unit('osperl', sub {}),
			      ),
	       new Maker::Seq($r->blib($inst),
			      $r->HashBang($linkage eq 'dyn'? 'perl' : 'osperl',
					   'ospeek'),
			      new Maker::Unit('ospeek', sub {}),
			      ),
	       $r->test_harness($linkage eq 'dyn'? 'perl' : 'osperl'),
	       $r->install($inst),
	       $r->uninstall($inst),
	       );
	$pk->clean(sub {
	    $pk->x("osrm -f $SchemaDir/perltest.db");
	});
    }
    { # perldb
	my $inst = { bin => [ 'perldb_util' ] };
	my $r = new Maker::Rules($pk, 'perl-module');
	$r->flags('cxx', "-I$Config{archlibexp}/CORE");
	$pk->a(new Maker::Seq($r->blib($inst),
			      new Maker::Phase('parallel',
					       $r->objstore($SchemaDir, 'perldb-01', [qw(compactor dbutil queries collections)]),
					       $r->cxx('edit.c'),
					       $r->embed_perl(),
					       $r->cxx('osperl.c'),
					       $r->cxx('hv_builtin.c'),
					       ),
			      $r->link('cxx', 'perldb_util'),
			      new Maker::Unit('util', sub{}),
			      ),
#	       $r->install($inst),
#	       $r->uninstall($inst),
	       );
    }
    $pk->load_argv_flags;
    $pk->top_go(@ARGV);
}
