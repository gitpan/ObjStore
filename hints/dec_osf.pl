# Thanks to Donald Buczek <buczek@mpimg-berlin-dahlem.mpg.de> for
# dec_osf hints and the initial Makefile.PL!

$self->{CC}="cxx -xtaso";
$self->{LD}="ld -taso";

defined $ENV{OS_ROOTDIR} or die "OS_ROOTDIR undefined\n";
$self->{LIBS}=["-L$ENV{OS_ROOTDIR}/lib -loscol -los -losthr"];

$self->{MAP_TARGET}="perl32";
$self->{LINKTYPE}="static";

$self->{INCLUDE_EXT}=[];


sub MY::top_targets {
        package MY;
        my $me=shift;
        return "all :: perl32\n\t$self->{NOECHO}\$(NOOP)\n"
                . $me->SUPER::top_targets(@_) . << '_EOF_';

osperl-08-schema.cc:
        ln -sf osperl-08-schema.c osperl-08-schema.cc

osperl-08-osschema.c: osperl-08-schema.cc
        ossg -xtaso $(INC) -I/usr/local/include $(DEFINE_VERSION) $(XS_DEFINE_VERSION) \
                -I$(PERL_INC) $(DEFINE) \
                -nout neutral-osperl-08 \
                -asdb /usr/tmp/joshua/osperl-08.adb \
                -assf osperl-08-osschema.c \
                osperl-08-schema.cc $(OS_ROOTDIR)/lib/liboscol.ldb

_EOF_
}


sub MY::c_o {
        return <<'_EOF_';
.c$(OBJ_EXT):
        ${CCCMD} $(CCCDLFLAGS) -I$(PERL_INC) $(DEFINE) -x cxx $*.c
_EOF_
}

sub MY::linkext {
        "linkext :: static dynamic\n\t$self->{NOECHO}\$(NOOP)";

}


#sub MY::cflags {
#warne->{CCFLAGS}.=" -xtaso";
#       return  $self->{CFLAGS} = qq{
#CCFLAGS = $self->{CCFLAGS}
#OPTIMIZE = $self->{OPTIMIZE}
#PERLTYPE = $self->{PERLTYPE}
#LARGE = $self->{LARGE}
#SPLIT = $self->{SPLIT}
#};
#
#}
