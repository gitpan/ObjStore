use strict;

#------------------------------------------------------------
package Worker;

package ObjStore::Tutorial;
use ObjStore;
use ObjStore::Table3;
use base 'ObjStore::Table3::Database';

sub new {
    my $class = shift;
    my $db = $class->SUPER::new(@_);
    $db->reset;
    $db;
}

sub report {
    use ObjStore::CSV;
    print_csv(shift->anyx,
	      calc => {
		       'boss' => sub {
			   my $boss = shift->boss;
			   $boss? $boss->name : 'nobody'
		       },
		      },
	     );
    ()
}

sub won {
    my ($o, $me) = @_;
    my $t = $o->table;
    $me ||= $t->{you};
    die "$o->table->{you} not found\n" if !$me;

    print "Checking to see if ".$me->name." has won...\n";

    my $win=1;
    my $loser;
    my $boss;

    my $a = $t->anyx;
    die "Couldn't find an index" if !$a;

    for (my $x=0; $x < $a->count; $x++) {
	$loser = $a->[$x];
	$boss = $loser->boss || 'nobody';
	my $loop=0;
	while ($loop < 100 && ref $boss && $boss->boss) {
	    die "Loop detected at ".$boss->name if ++$loop > 100;
	    $boss = $boss->boss; 
	}
	next if $loser == $me && !ref($boss);
	if ($boss != $me) { $win=0; last }
    }
    if ($win) { print "  Congratuations!  ".$me->name." wins!\n"; }
    else {
	$boss = $boss->name if ref $boss;
	print "  '".$loser->name."' works for '$boss';\n";
	print "  You haven't won until everybody works for you!\n";
    }
    ()
}

sub reset {
    my ($db) = @_;
    my $t = $db->table->CLEAR;

    my $x = new ObjStore::Index($db, path => "lastname, firstname");
    $t->add_index('name', $x);
    my $c = $x->new_cursor;
    
    my @men = qw(Harry Dick Bob Smith Jose Hans);
    my @women = qw(Tiffany Rose Donna Lisa Mia Kathy Jennie);
    my @surname = qw(Wang Baker Prince Gans Choi Curry);

    for (1..24) {
	my ($first,$last);
	do {
	    if (rand > .5) {
		$first = $women[int(rand(@women))];
	    } else {
		$first = $men[int(rand(@men))];
	    }
	    $last = $surname[int(rand(@surname))];
	} while ($c->seek($last,$first));

	# Once they are added to the index, the first & last names
	# are marked read-only.  To change them, you have to take
	# them out of the index, make the change, and re-add them.

	$t->add(new Worker($db, $last, $first));
    }
    for (my $i=0; $i < $x->count; $i++) {
	$x->[$i]->boss($x->[int(rand($x->count))]);
    }
    $t->{you} ||= new Worker($db, "Winner", "Potential");
    ();
}

#------------------------------------------------------------
package Worker;
use ObjStore;
use base 'ObjStore::HV';

sub new {
    my ($class, $where, $last, $first) = @_;
    $class->SUPER::new($where, { firstname => $first, lastname => $last });
}

sub name {
    my ($o) = @_;
    "$o->{firstname} $o->{lastname}";
}

sub boss {
    my ($o, $nb) = @_;
    if (@_ == 2) {
	if ($o == $nb) { delete $o->{boss}; }
	else           { $o->{boss} = $nb;  }
    }
    $o->{boss};
}

1;
