#!/usr/local/bin/perl -w

use Data::Dumper;
use lib '.';
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
    
    $pk->default_targets('osperl', 'ospeek');

    { # osperl
	my $inst = {
	    bin => [ 'osperl' ],
	    script => [ 'ospeek' ],
	    man3 => [ 'ObjStore.3' ],
	    lib => [ 'ObjStore.pm', 'PoweredByOS.gif' ]};
	
	my $r = Maker::Rules->new($pk, 'perl-module');
	$pk->a(new Maker::Seq($r->blib($inst), 
			      new Maker::Phase('parallel',
					       $r->embed_perl('ObjStore'),
					       $r->objstore($SchemaDir, 'osperl-3',
							    ['collections']),
					       $r->xs('ObjStore.xs'),
					       $r->cxx('osperl.c')
					       ),
			      $r->link('cxx', './blib/bin/osperl'),
			      $r->pod2man('ObjStore.pm', 3),
			      $r->populate_blib($inst),
			      new Maker::Unit('osperl', sub {}),
			      ),
	       new Maker::Seq($r->blib($inst),
			      $r->HashBang('osperl', 'ospeek'),
			      new Maker::Unit('ospeek', sub {}),
			      ),
	       $r->test_harness('./blib/bin/osperl'),
	       $r->install($inst),
	       $r->uninstall($inst),
	       );
	$pk->clean(sub {
	    $pk->x("osrm -f $SchemaDir/perltest.db");
	});
    }
    { # ospevo
	my $inst = { bin => [ 'ospevo' ] };
	my $r = new Maker::Rules($pk, 'perl-module');
	$r->flags('cxx', "-I$Config{archlibexp}/CORE");

	$pk->a(new Maker::Seq($r->blib($inst),
			      new Maker::Phase('parallel',
					       $r->objstore($SchemaDir, 'ospevo-1', [qw(evolution queries mop dbutil collections)]),
					       $r->cxx('evo.c'),
					       ),
			      $r->link('cxx', 'ospevo'),
			      new Maker::Unit('ospevo', sub{}),
			      ),
	       $r->install($inst),
	       $r->uninstall($inst),
	       );
    }
#    print Dumper($pk);
    $pk->load_argv_flags;
    $pk->top_go(@ARGV);
}
