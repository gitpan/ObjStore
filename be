#!/usr/local/bin/perl -w

use lib '.';
use Devel::Maker;

{
    # Specify a good directory for the application schema:
    my $SchemaDir = '/opt/os/joshua';
    
    my $pkg = {
	name => 'ObjStore',
	optimize => 1,
	build => sub {
	    my ($o) = @_;
	    $o->embed_perl('ObjStore');
	    $o->objstore($SchemaDir, 'osperl', ['collections']);
	    $o->xs('ObjStore.xs');
	    $o->cxx('osperl.c');
	    $o->link('cxx', './blib/bin/osperl');
	},
	test_bin => './blib/bin/osperl',
	install_map => {
	    'bin' => [ 'osperl' ],
	    'man3' => [ 'ObjStore.pm' ],
	    'lib' => [ 'ObjStore.pm', 'PoweredByOS.gif' ],
	},
	clean => [qw(osperl-osschema.* ObjStore.c osperl)],
    };

    my $o = new Devel::Maker($pkg);
    $o->pm_2version('ObjStore.pm');

    $o->help('1. Please set the following environment variables before compiling:

OS_ROOTDIR=/nw/dist/vendor/os/4.0.2/sunpro (or whatever)
OS_LDBBASE=/export2/os/4.0.2/sunpro (as appropriate)
 
PATH+=$OS_ROOTDIR/bin ; LD_LIBRARY_PATH+=$OS_ROOTDIR/lib
 
2. Make sure you pick a reasonable directory for the application schema.
See $SchemaDir in the be file.

');

    $o->go('all');
}

