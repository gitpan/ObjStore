
$self->{CC}="cxx -xtaso";
$self->{PERLMAINCC}="cc -xtaso";
$self->{LIBS}=["-L$ENV{OS_ROOTDIR}/lib -loscol -los -losthr"];


# link with cxx ! it adds cxx release specific objects...

#$self->{LD}="cxx -taso -g";   

$self->{LD}="cxx -taso -v -g";  # cxx forgets to propagate -g :-)
$self->{LDDLFLAGS}='-shared -expect_unresolved "*" -O4 -msym -L/usr/local/lib'; # remove -s, if you want debugging

$self->{MAP_TARGET}="perl32";
$self->{LINKTYPE}="static";

check_cxx_version();

sub check_cxx_version {
	my $out=`cxx -V`;
	die "cant run cxx\n" if @?;
	return if $out=~/\QV5.5-004/;

	warn "$out\n";

 	die "Your compiler Version wont work\n" if $out=~/\QT5.6-009/;

	warn "Compiler version untested\n";
}


package MY;

sub install {
	my $out=shift->SUPER::install(@_);

	# We do NOT want our ObjStore.a or our extralibs.ld to be installed
	# in INSTALL_ARCHLIB. If we do, other modules couldn't be linked
	# static, because they would try to include ObjStore.a and the
	# ObjectStore libraries. And other modules wont have OS_ROOTDIR
	# defined, dont need it and are not -xtaso anyway.
	#
	# To remove these from blib would need many changes to
	# MM_Unix. So we create them in blib (where we need them to link
	# our perl32) and skip them only during install.

	$out=~s/^.*INST_ARCHLIB.*\n//gm;
	$out;
}

sub c_o {
	my $out=shift->SUPER::c_o;

	# wish, joshua didn't call his C++ files .c. So we need to modify
	# our .c.o rule to tell cxx, that our .c files really are C++ source

	$out=~s/\$\*\.c/-x cxx \$*.c/;
	$out;

}

sub cflags {

	my $out=shift->SUPER::cflags(@_);
	#
	# DEC cxx5.5 doesn't know the -std flags, which we possibly used
	# to compile perl with cc. cxx 5.6 does.
	#
	$out=~s/-std//;             # cxx5.5-004 doesnt want this.
      $out=~s/-fprm d//;          # buggy if given cxx forgets to pass args to cc :-)
	$out;
}

#
# Overlay Makefile.PLs postamble :-)
# we want to add something to the makefile.
#
# create our perl executable as a default.
#
#

# MY::postamble allready defined by Makefile.PL.
# we are going to redefine it. Save old method.

BEGIN { $HINTS::old_postamble = \&postamble; }

sub postamble {
	my $out = &$HINTS::old_postamble(@_);

	#
	# add -xtaso flag to the ossg rule
	#

	$out=~s/^(\t\s*)ossg(\s)/$1ossg -xtaso$2/gm;
	$out.<<'_EOF_';
all :: $(MAP_TARGET)
pure_install :: $(MAP_TARGET)
	$(MAKE) -f $(MAKE_APERL_FILE) pure_inst_perl
_EOF_
}

