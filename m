#!/usr/local/bin/perl -w

use lib '.';
use Devel::Maker;

{
    # Specify a good directory for the application schema - $SchemaDir
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
	    'sitelib' => [ 'ObjStore.pm' ],
	},
	clean => [qw(osperl-osschema.* ObjStore.c osperl)],
    };

    my $o = new Devel::Maker($pkg);
    $o->pm_2version('ObjStore.pm');

    $o->help('
1. Please set the following environment variables before compiling:

OS_ROOTDIR=/nw/dist/vendor/os/4.0.2/sunpro
OS_LDBBASE=/export2/os/4.0.2/sunpro
 
PATH+=$OS_ROOTDIR/bin
LD_LIBRARY_PATH+=$OS_ROOTDIR/lib
MANPATH+=$OS_ROOTDIR/man
 
2. All *.ldb files must be on the osserver\'s local filesystem.

3. Also, make sure you pick a reasonable directory for the application schema.

');

    $o->go('all');
}

