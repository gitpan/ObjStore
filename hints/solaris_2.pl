$self->{CC}="CC -vdelx -pta";
$self->{LD}="CC -ztext";
$self->{CCCDLFLAGS}="-KPIC";
$self->{clean} = {FILES => 'Templates.DB'};
$self->{PERLMAINCC} = 'gcc';
$self->{LIBS} = ["-R$ENV{OS_ROOTDIR}/lib -loscol -los -losths -lC"];
