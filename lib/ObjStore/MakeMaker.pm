use 5.00404;
use strict;
package ObjStore::MakeMaker;
use ObjStore::Config qw(DEBUG);
use Config;
require Exporter;
use vars qw(@ISA @EXPORT_OK %EXPORT_TAGS
	    $CXX $OS_ROOTDIR $OS_LIBDIR);
@ISA       = 'Exporter';
@EXPORT_OK = qw($OS_ROOTDIR $OS_LIBDIR
		&add_os_args &os_schema_rule);
%EXPORT_TAGS = (ALL => \@EXPORT_OK);

# ++$main::Verbose;

$CXX = 'c';  # the .ext for C++ files; get from hints? XXX

my $libosperl;
$OS_ROOTDIR = $ENV{OS_ROOTDIR} ||
    die "ObjStore::Config: please set \$ENV{OS_ROOTDIR}!\n";
$OS_LIBDIR = $ENV{OS_LIBDIR} || "$ENV{OS_ROOTDIR}/lib";

sub in_main_dist {
    for (1..3) {
	my $dot = join '/', ('..')x$_;
	return $dot if -e "$dot/lib/ObjStore.pm" && -e "$dot/lib/ObjStore.pod";
    }
    ''
}

# add this to MY::postamble
sub os_schema_rule {
    my ($schema, @LDB) = @_;
    my $dir = $ObjStore::Config::SCHEMA_DBDIR;
    if ($schema =~ s,^(.*)/,,) {
	$dir = $1;
    }

    my $out = $schema;
    $out =~ s/.sch$/.$CXX/;

    my $db = $schema;
    $db =~ s/.sch$/.adb/;

    '
'.$out.' :: '.$schema.' $(H_FILES)
	ossg -DOSSG=1 $(INC) $(DEFINE_VERSION) $(XS_DEFINE_VERSION) \
	  -I$(PERL_INC) $(DEFINE) -showw -nout neutral.out \
	  -asdb '.$dir.'/'.$db.' \
	  -assf '.$out.' \
	  '.$schema.' '.join(' ',@LDB).'

clean ::
	-rm -f '.$out.' neutral.out
'
}

sub add_os_args {
    my $libs = [];
    $libs = shift if ref $_[0];
    my %arg = @_;

     # side step an annoying bug in tied filehandles
    $arg{XSPROTOARG} .= '-nolinenumbers' if $] < 5.00460;
    $arg{LINKTYPE} = 'dynamic';

    my $top = in_main_dist();
    if ($top) {
	$arg{VERSION_FROM} = "$top/lib/ObjStore.pm";
	if (!-e 'hints') {
	    # if your not part of the main dist, you're on your own
	    symlink "$top/hints", "hints" or warn "symlink hints: $!";
	}
    }
    $arg{DEFINE} .= ' -DOSP_DEBUG' if DEBUG;
    $arg{INC} .= " -I$OS_ROOTDIR/include";
    $arg{LIBS} ||= [''];

    # some architectures only use -losthr no matter what?
    my $thrlib = $Config{usethreads} ? '-losthr' : '-losths';
    my $strip = "-L$ENV{OS_ROOTDIR}/lib";

    if ($arg{NAME} =~ m/^libosperl/) {
	for (@{$arg{LIBS}}) {
	    $_ .= " $strip ".join(' ',@$libs)." -los $thrlib -lC";
	}
    } else {
	# must build to libosperl\d\d.so for a clean link
	if ($top) {
	    $arg{INC} .= " -I$top/API";
	    push @{ $arg{TYPEMAPS} }, "$top/API/typemap";

#	    push @M, BLIB_LIBS=>{ '-losperl'.&ObjStore::Config::API_VERSION =>
#				  ["-L$top/blib/arch/auto/ObjStore",
#				   "-L$Config{sitearch}/auto/ObjStore"] };
	    my $ospdir = "-L$Config{sitearch}/auto/ObjStore";
	    for (@{$arg{LIBS}}) {
		$_ .= (" $strip ".join(' ',@$libs)." $ospdir -losperl".
		       &ObjStore::Config::API_VERSION);
	    }
	} else {
	    $arg{INC} .= " -I$Config{sitearch}/auto/ObjStore";
	    push @{$arg{TYPEMAPS}}, "$Config{sitearch}/auto/ObjStore/typemap";
	    for (@{$arg{LIBS}}) {
		$_ .= (" $strip ".join(' ', @$libs).
		       " -L$Config{sitearch}/auto/ObjStore -losperl".
		       &ObjStore::Config::API_VERSION);
	    }
	}
    }
    %arg;
}

1;
