$self->{CC}="CC -vdelx -pta";
$self->{LD}="CC -ztext";

# purify:
#   export PUREOPTIONS="-cache-dir=/tmp/purify -always-use-cache-dir -chain-length=10 -best-effort"
#   ar r ObjStore.a Templates.DB/*.o
#   edit MAP_LINKCMD by hand for purify
#  ??

$self->{CCCDLFLAGS}="-KPIC";
$self->{clean} = {FILES => 'Templates.DB'};
$self->{PERLMAINCC} = 'gcc';
$self->{LIBS} = ["-R$ENV{OS_ROOTDIR}/lib -loscol -los -losths -lC"];
