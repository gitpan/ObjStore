use 5.00404;
use strict;
package ObjStore::Config;
use Config;
require Exporter;
use vars qw(@ISA @EXPORT @EXPORT_OK %EXPORT_TAGS
	    $Debug $CXX $OS_ROOTDIR $OS_LIBDIR $OSPERL_SCHEMA_VERSION);
@ISA       = 'Exporter';
@EXPORT    = qw(&TMP_DBDIR);
@EXPORT_OK = qw(&SCHEMA_DBDIR $OS_ROOTDIR $OS_LIBDIR $OSPERL_SCHEMA_VERSION
		&os_stdargs &os_schema_rule);
%EXPORT_TAGS = (ALL => [@EXPORT, @EXPORT_OK]);

# Turn on extra checking (orthogonal to -DDEBUGGING)

$Debug = 1;

# Specify a directory for the application schema (and recompile):
# (override with $ENV{OSPERL_SCHEMA_DB})

sub SCHEMA_DBDIR() { 'elvis:/data/research/schema' }

# Specify a directory for temporary databases (posh, perltest, etc):

sub TMP_DBDIR() { 'elvis:/data/research/tmp' }

# Paths should not have a trailing slash.

#------------------------------------------------------------------------

$CXX = 'c';  # the .ext for C++ files; get from hints? XXX

my $libosperl;
$OS_ROOTDIR = $ENV{OS_ROOTDIR} ||
    die "ObjStore::Config: please set OS_ROOTDIR!\n";
$OS_LIBDIR = $ENV{OS_LIBDIR} || "$ENV{OS_ROOTDIR}/lib";

$OSPERL_SCHEMA_VERSION = '12';

sub in_main_dist {
    '.'
}

# add this to MY::postamble
sub os_schema_rule {
    my ($schema, @LDB) = @_;
    my $dir = &SCHEMA_DBDIR;
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

sub os_stdargs {
    my ($p,$libs) = @_;
    $libs ||= [];
    $libosperl = $p =~ m/^libosperl/;
    my $top = in_main_dist();

    my (@M,@D);
    my @I = ("-I$OS_ROOTDIR/include");
    push @D, '-DOSP_DEBUG' if $Debug;
    push @M, VERSION_FROM => "$top/lib/ObjStore.pm" if $top;

    my $thrlib = $Config{usethreads} ? '-losthr' : '-losths';
    my ($strip,$sym) = map { "-L$ENV{OS_ROOTDIR}/$_" } 'lib','debug/lib';

    if ($top and !-e 'hints') {
	# if your not part of the main dist, you're on your own
	symlink "$top/hints", "hints" or warn "symlink hints: $!";
    }
    push @M, TYPEMAPS => ["$top/typemap"];
    push @M, LIBS => ["$strip ".join(' ',@$libs)." -los $thrlib -lC"];

    push(@M,
	 NAME => $p,
	 INC => join(' ', @I),
	 DEFINE => join(' ', @D),
	 LINKTYPE => 'dynamic',
	 dist => {COMPRESS=>'gzip -9f', SUFFIX => 'gz'});

	 # side step an annoying bug in tied filehandles
	 XSPROTOARG => '-prototypes '.($] < 5.00460? '-nolinenumbers' : ''),
    @M
}

1;
