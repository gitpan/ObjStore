#!/usr/local/bin/perl -w

use lib '.';
#use lib '/home/joshua/Maker-2.05';
use Config;
require Maker::Package;
require Maker::Rules;

require './Config.pm';
ObjStore::Config->import(':ALL');

my $pk = new Maker::Package(top=>'ObjStore');
$pk->pm_2version('ObjStore.pm');
$pk->post_help('1. Please set the following environment variables before compiling:

  OS_ROOTDIR=/nw/dist/vendor/os/4.0.2/sunpro (or whatever)
  OS_LIBDIR=$OS_ROOTDIR/lib (as appropriate)
  PATH+=$OS_ROOTDIR/bin ; LD_LIBRARY_PATH+=$OS_ROOTDIR/lib
 
2. Please edit "./Config.pm" to your preference.

');

# build just one target, i.e. 'be osp'
my @scripts = qw(ospeek osp_copy posh);
$pk->default_targets('blib', 'osp',  @scripts);

my $inst = {
    bin =>    [], #['osp_evolve'],
    script => [@scripts],
    man3 =>   ['ObjStore.3', 'ObjStore::Table2.3', 'ObjStore::Tutorial.3'],
    lib =>    ['ObjStore.pm', 'ObjStore/',
	       'ObjStore/Config.pm', 'ObjStore/GENERIC.pm',
	       'ObjStore/Path/',
	       'ObjStore/Path/Ref.pm', 'ObjStore/Path/Cursor.pm',
	       'ObjStore/Table.pm', 'ObjStore/Table2.pm',
	       'ObjStore/Tutorial.pm',
	       'ObjStore/AppInstance.pm',
	       'ObjStore/CSV.pm', 'ObjStore/Peeker.pm',
	       'ObjStore/SetEmulation.pm',
	       'ObjStore/PoweredByOS.gif', 'ObjStore/ObjStore.html', 
	       'ObjStore/Table2.html', 'ObjStore/Tutorial.html',
	       ($] < 5.00450? 'base.pm':())],
};

if (&LINKAGE eq 'dyn') {
    $inst->{arch} = ['auto/ObjStore/', 'auto/ObjStore/ObjStore.so'];
}
else { $inst->{bin} = ['osperl']; }

my $r = Maker::Rules->new($pk, 'perl-module');
@build_scripts = map {
    new Maker::Seq($r->HashBang(&LINKAGE eq 'dyn'? 'perl' : 'osperl', $_),
		   new Maker::Unit($_, sub {})) } @scripts;
$r->opt(1);
#$r->flags('cxx', '-O');
$r->flags('cxx', '-DOSP_DEBUG', '-DDEBUGGING');
#$r->flags('ossg', '-padc', '-arch','set1');
$r->flags('ld-dl', '-ztext');   # SunPro specific?
$r->flags('xsubpp', "-nolinenumbers"); #line numbers tickle a BUS error :-(
my $build =
    new Maker::Seq(new Maker::Phase('parallel',
				    (&LINKAGE eq 'static' ?
				     ($r->cxx('perlmain.c'),
				      $r->embed_perl('ObjStore')) :
				     ()),
				    $r->objstore(&SCHEMA_DBDIR, 'osperl-08',
						 ['collections']),
				    $r->cxx('osperl.c'),
				    $r->cxx('txn.c'),
				    $r->xs('GENERIC.xs'),
				    $r->xs('ObjStore.xs'),
				    ),
		   (&LINKAGE eq 'dyn'?
		    $r->dlink('cxx', './blib/arch/auto/ObjStore/ObjStore.so') :
		    $r->link('cxx', './blib/bin/osperl')));

$pk->a(new Maker::Seq(new Maker::Phase($build,
				       $r->pod2man('ObjStore.pod', 3),
				       $r->pod2html('ObjStore.pod'),
				       $r->pod2man('Table2.pm', 'ObjStore::Table2.3'),
				       $r->pod2html('Table2.pm'),
				       $r->pod2man('Tutorial.pm', 'ObjStore::Tutorial.3'),
				       $r->pod2html('Tutorial.pm'),
				      ),
		      $r->blib($inst),
		      $r->populate_blib($inst),
		      new Maker::Unit('osp', sub {}),
		      ),
       @build_scripts,
       new Maker::Seq($r->blib($inst),
		      new Maker::Unit('blib', sub {})),
       $r->test_harness(&LINKAGE eq 'dyn'? 'perl' : 'osperl'),
       $r->install($inst),
       $r->uninstall($inst),
       );
$pk->clean(sub {
    $pk->x("osrm -f ".&SCHEMA_DBDIR."/perltest");
});

$r = new Maker::Rules($pk, 'perl-module');
$r->flags('cxx', "-I$Config{archlibexp}/CORE");
$r->flags('cxx', $r->flags('cxx-dl')) if &LINKAGE eq 'dyn';
$pk->a(new Maker::Seq(new Maker::Phase('parallel',
				       $r->objstore(&SCHEMA_DBDIR, 'osp-evolve-02', [qw(evolution mop queries collections)]),
				       $r->cxx('edit.c'),
				       $r->embed_perl(),
				       $r->cxx('osperl.c'),
				       $r->xs('GENERIC.xs'),
				       ),
		      $r->link('cxx', 'osp_evolve'),
		      new Maker::Unit('evo', sub{}),
		      ),
       );
$pk->load_argv_flags;
$pk->top_go(@ARGV);