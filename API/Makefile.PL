#!./perl -w
# This is the generic part.

use strict;
use ExtUtils::MakeMaker;
# $Verbose = 1;

use lib '../lib';
use ObjStore::MakeMaker ':ALL';

my $v = &ObjStore::Config::SCHEMA_VERSION;

my @L = qw[osp-preamble.h osperl.h XSthr.h typemap];
my %args = (
	    NAME => "libosperl",
# DEFINE => " -DOSP_SAFE_BRIDGE",    # increment refcnts on reads?
	    OBJECT => "osperl.o txn.o Core.o osperl-$v.o",
	    PM => { map { ($_ => '$(INST_AUTODIR)/'.$_) } @L },
);
WriteMakefile(add_os_args([], %args));

sub MY::postamble { os_schema_rule("osperl-$v.sch") }

# We use the non-default name 'libosperl01.so' because the main
# ObjStore.xs uses ObjStore.so and we want something suitably
# different.  But we still want the library installed under
# auto/ObjStore/.  The idea is to forcibly limit the link dependencies
# to stuff in this library.

package MY;
sub constants {
    my $str = shift->SUPER::constants;
    $str =~ s/^(FULLEXT) = .*$/$1 = ObjStore/gm;
    $str;
}
