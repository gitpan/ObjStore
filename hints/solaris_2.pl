if (1) {
    $self->{CC}="CC -vdelx -pta";
    $self->{LD}="CC -ztext";
} else {
    # Insure++ is amazing!  http://www.parasoft.com
    $self->{CC} = "insure -Zoi 'compiler CC' -vdelx -pta";
    $self->{LD} = "insure -Zoi 'compiler CC' -ztext";
    $self->{OPTIMIZE} = '-g';
}

$self->{CCCDLFLAGS} = "-KPIC";
$self->{clean}{FILES} .= ' Templates.DB';
$self->{PERLMAINCC} = 'gcc';

