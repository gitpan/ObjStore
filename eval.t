require Eval;

my $ev = new Eval();
warn 'setup';
$ev->eval("  warn 'hm';  die 'this is silly'; ", 'fake', 0);
exit if !$ev->ok;
warn 'ready';
eval {
	$ev->x();
};
warn $@;
warn 'ok';


