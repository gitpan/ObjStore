use strict;

=head1 NAME

  ObjStore::Tutorial - A Gentle Introduction

=head1 SYNOPSIS

This silly tutorial will help you become familiar with OS/Perl!

The HTML version is easier to read than the man page version.

=head1 DESCRIPTION

C<I</home/joshua%> B<posh>>

  posh 1.21 (Perl 5.00454 ObjectStore Release 5.0.1.0)
  [set for READ]

C<I</home/joshua%> B<cd /opt/os/tmp>>

C<I</opt/os/tmp%> B<help>>

  Outside of databases:
     cd <dir>
     cd <db> [class [inc]]  # enters <db> or $class->new("update", 0666)
     ls <dir>
     pwd
  Inside of databases:
     cd string           # interprets string according to $at->POSH_CD
     cd $at->...         # your expression should evaluate to a ref
     cd ..               # what you expect
     ls
     peek                # ls but more
     rawpeek             # ignore special POSH_PEEK methods
     pwd
     <or any perl statement!>
  Change transaction mode:
     read
     update
     abort_only

C<I</opt/os/tmp%> B<ls>>

  perltest      posh

C<I</opt/os/tmp%> B<cd tutor ObjStore::Tutorial>>

  [creating tutor]

C<I<$at = ObjStore::Table2=REF(0xe39809b8)%> B<ls>>

  $at = TABLE ObjStore::Table2 {
    array[18] of Worker ...
    indices: NAME;
  },

C<I<$at = ObjStore::Table2=REF(0xe39809b8)%> B<$db-E<gt>won>>

  Checking to see if Ms. Subject has won...
    'Ms. Subject' works for 'Mr. Substituent';
    You haven't won until everybody works for you.

C<I<$at = ObjStore::Table2=REF(0xe39809b8)%> B<ls $db-E<gt>me>>

  [0] = Worker {
    boss => Worker ...
    name => 'Ms. Subject',
  },

C<I<$at = ObjStore::Table2=REF(0xe39809b8)%> B<$db-E<gt>report>>

  index	boss	boss_name	name
  0	Worker=REF(0xe3981714)	Mr. Substituent	Ms. Subject
  1	Worker=REF(0xe3981714)	Mr. Substituent	Mr. Subliminal
  2	Worker=REF(0xe3981394)	Ms. Subtracter	Mr. Submersible
  3	Worker=REF(0xe3981a2c)	Mr. Subsistent	Ms. Subrogation
  4	Worker=REF(0xe39812b4)	Mr. Subterfuge	Mr. Subservient
  5	Worker=REF(0xe3981714)	Mr. Substituent	Mr. Subsidiary
  6	Worker=REF(0xe3980f48)	Ms. Subject	Ms. Subsidy
  7	Worker=REF(0xe3980f48)	Ms. Subject	Mr. Subsistent
  8	Worker=REF(0xe3981394)	Ms. Subtracter	Ms. Substantial
  9	Worker=REF(0xe3981b48)	Ms. Substantial	Ms. Substantive
  10	Worker=REF(0xe3981b48)	Ms. Substantial	Mr. Substituent
  11	Worker=REF(0xe39812b4)	Mr. Subterfuge	Mr. Substitute
  12	Worker=REF(0xe3980f48)	Ms. Subject	Ms. Substrate
  13	Worker=REF(0xe3981634)	Ms. Subrogation	Mr. Subterfuge
  14	Worker=REF(0xe3980f48)	Ms. Subject	Mr. Subterran
  15	Worker=REF(0xe3981a2c)	Mr. Subsistent	Ms. Subtracter
  16	Worker=REF(0xe3981554)	Mr. Submersible	Ms. Subtrahend
  17	Worker=REF(0xe3981634)	Ms. Subrogation	Mr. Subvert
  18	boss	boss_name	name

C<I<$at = ObjStore::Table2=REF(0xe39809b8)%> B<update>>

  [set for UPDATE]

C<I<$at = ObjStore::Table2=REF(0xe39809b8)%> B<$db-E<gt>me-E<gt>name("Joshua")>>

  $fake1 = 'Joshua',

C<I<$at = ObjStore::Table2=REF(0xe39809b8)%> B<ls $db-E<gt>me>>

  [0] = Worker {
    boss => Worker ...
    name => 'Joshua',
  },

C<I<$at = ObjStore::Table2=REF(0xe39809b8)%> B<$db-E<gt>me-E<gt>boss($db-E<gt>me)>>

  $fake1 = undef,

C<I<$at = ObjStore::Table2=REF(0xe39809b8)%> B<ls $db-E<gt>me>>

  [0] = Worker {
    name => 'Joshua',
  },

C<I<$at = ObjStore::Table2=REF(0xe39809b8)%> B<$db-E<gt>report>>

  index	boss_name	name
  0	nobody	Joshua
  1	Mr. Substituent	Mr. Subliminal	Worker=REF(0xe3981714)
  2	Ms. Subtracter	Mr. Submersible	Worker=REF(0xe3981394)
  3	Mr. Subsistent	Ms. Subrogation	Worker=REF(0xe3981a2c)
  4	Mr. Subterfuge	Mr. Subservient	Worker=REF(0xe39812b4)
  5	Mr. Substituent	Mr. Subsidiary	Worker=REF(0xe3981714)
  6	Joshua	Ms. Subsidy	Worker=REF(0xe3980f48)
  7	Joshua	Mr. Subsistent	Worker=REF(0xe3980f48)
  8	Ms. Subtracter	Ms. Substantial	Worker=REF(0xe3981394)
  9	Ms. Substantial	Ms. Substantive	Worker=REF(0xe3981b48)
  10	Ms. Substantial	Mr. Substituent	Worker=REF(0xe3981b48)
  11	Mr. Subterfuge	Mr. Substitute	Worker=REF(0xe39812b4)
  12	Joshua	Ms. Substrate	Worker=REF(0xe3980f48)
  13	Ms. Subrogation	Mr. Subterfuge	Worker=REF(0xe3981634)
  14	Joshua	Mr. Subterran	Worker=REF(0xe3980f48)
  15	Mr. Subsistent	Ms. Subtracter	Worker=REF(0xe3981a2c)
  16	Mr. Submersible	Ms. Subtrahend	Worker=REF(0xe3981554)
  17	Ms. Subrogation	Mr. Subvert	Worker=REF(0xe3981634)
  18	boss_name	name	boss

C<I<$at = ObjStore::Table2=REF(0xe39809b8)%> B<$db-E<gt>won>>

  Checking to see if Joshua has won...
    Congratuations!  Joshua wins!

[I got lucky because the randomly created database already had
everyone working for me.  You may not have been so lucky with your
database.  In any case, continue reading and things will make sense.]

C<I<$at = ObjStore::Table2=REF(0xe39809b8)%> B<$db-E<gt>reset>>

  $fake1 = ObjStore::Tutorial[/opt/os/tmp/tutor, update] {
    table => TABLE ObjStore::Table2 {
      array[18] of Worker {
        boss => Worker {
          boss => Worker {
            boss => Worker {
              boss => Worker {
                boss => Worker ...
                name => 'Ms. Subliminal',
              },
              name => 'Ms. Subsidy',
            },
            name => 'Ms. Substituent',
          },
          name => 'Mr. Subtracter',
        },
        name => 'Ms. Subject',
      },
      indices: NAME;
    },
  },

C<I<$at = ObjStore::Table2=REF(0xe39809b8)%> B<$db-E<gt>report>>

  index	boss	boss_name	name
  0	Worker=REF(0xe39819d0)	Mr. Subtracter	Ms. Subject
  1	Worker=REF(0xe3981554)	Ms. Subsidy	Ms. Subliminal
  2	Worker=REF(0xe39819d0)	Mr. Subtracter	Ms. Submersible
  3	Worker=REF(0xe3981f08)	Ms. Subliminal	Mr. Subrogation
  4	Worker=REF(0xe3981554)	Ms. Subsidy	Ms. Subservient
  5	Worker=REF(0xe3981634)	Mr. Subsistent	Ms. Subsidiary
  6	Worker=REF(0xe3981f08)	Ms. Subliminal	Ms. Subsidy
  7	Worker=REF(0xe3981e98)	Ms. Subject	Mr. Subsistent
  8	Worker=REF(0xe3981324)	Mr. Subterfuge	Ms. Substantial
  9	Worker=REF(0xe3981554)	Ms. Subsidy	Mr. Substantive
  10	Worker=REF(0xe3981554)	Ms. Subsidy	Ms. Substituent
  11	undef	nobody	Mr. Substitute
  12	Worker=REF(0xe3981394)	Ms. Subterran	Mr. Substrate
  13	Worker=REF(0xe3980f48)	Mr. Subrogation	Mr. Subterfuge
  14	Worker=REF(0xe3981634)	Mr. Subsistent	Ms. Subterran
  15	Worker=REF(0xe3981784)	Ms. Substituent	Mr. Subtracter
  16	Worker=REF(0xe3981e98)	Ms. Subject	Mr. Subtrahend
  17	undef	nobody	Ms. Subvert
  18	boss	boss_name	name

C<I<$at = ObjStore::Table2=REF(0xe39809b8)%> B<$db-E<gt>me-E<gt>name("Joshua")>>

  $fake1 = 'Joshua',

C<I<$at = ObjStore::Table2=REF(0xe39809b8)%> B<$db-E<gt>me-E<gt>boss($db-E<gt>me)>>

  $fake1 = undef,

C<I<$at = ObjStore::Table2=REF(0xe39809b8)%> B<$db-E<gt>won>>

  Checking to see if Joshua has won...
    'Ms. Subliminal' works for 'Ms. Subsidy';
    You haven't won until everybody works for you.

C<I<$at = ObjStore::Table2=REF(0xe39809b8)%> B<$db-E<gt>report>>

  index	boss_name	name
  0	nobody	Joshua
  1	Ms. Subsidy	Ms. Subliminal	Worker=REF(0xe3981554)
  2	Mr. Subtracter	Ms. Submersible	Worker=REF(0xe39819d0)
  3	Ms. Subliminal	Mr. Subrogation	Worker=REF(0xe3981f08)
  4	Ms. Subsidy	Ms. Subservient	Worker=REF(0xe3981554)
  5	Mr. Subsistent	Ms. Subsidiary	Worker=REF(0xe3981634)
  6	Ms. Subliminal	Ms. Subsidy	Worker=REF(0xe3981f08)
  7	Joshua	Mr. Subsistent	Worker=REF(0xe3981e98)
  8	Mr. Subterfuge	Ms. Substantial	Worker=REF(0xe3981324)
  9	Ms. Subsidy	Mr. Substantive	Worker=REF(0xe3981554)
  10	Ms. Subsidy	Ms. Substituent	Worker=REF(0xe3981554)
  11	nobody	Mr. Substitute
  12	Ms. Subterran	Mr. Substrate	Worker=REF(0xe3981394)
  13	Mr. Subrogation	Mr. Subterfuge	Worker=REF(0xe3980f48)
  14	Mr. Subsistent	Ms. Subterran	Worker=REF(0xe3981634)
  15	Ms. Substituent	Mr. Subtracter	Worker=REF(0xe3981784)
  16	Joshua	Mr. Subtrahend	Worker=REF(0xe3981e98)
  17	nobody	Ms. Subvert
  18	boss_name	name	boss

C<I<$at = ObjStore::Table2=REF(0xe39809b8)%> B<ls>>

  $at = TABLE ObjStore::Table2 {
    array[18] of Worker ...
    indices: NAME;
  },

C<I<$at = ObjStore::Table2=REF(0xe39809b8)%> B<$at-E<gt>fetch('name', 'Ms. Subliminal')>>

  $fake1 = Worker {
    boss => Worker {
      boss => Worker ...
      name => 'Ms. Subsidy',
    },
    name => 'Ms. Subliminal',
  },

C<I<$at = ObjStore::Table2=REF(0xe39809b8)%> B<$at-E<gt>fetch('name', 'Ms. Subliminal')-E<gt>boss-E<gt>boss($db-E<gt>me)>>

  $fake1 = Worker {
    name => 'Joshua',
  },

C<I<$at = ObjStore::Table2=REF(0xe39809b8)%> B<$db-E<gt>report>>

  index	boss_name	name
  0	nobody	Joshua
  1	Ms. Subsidy	Ms. Subliminal	Worker=REF(0xe3981554)
  2	Mr. Subtracter	Ms. Submersible	Worker=REF(0xe39819d0)
  3	Ms. Subliminal	Mr. Subrogation	Worker=REF(0xe3981f08)
  4	Ms. Subsidy	Ms. Subservient	Worker=REF(0xe3981554)
  5	Mr. Subsistent	Ms. Subsidiary	Worker=REF(0xe3981634)
  6	Joshua	Ms. Subsidy	Worker=REF(0xe3981e98)
  7	Joshua	Mr. Subsistent	Worker=REF(0xe3981e98)
  8	Mr. Subterfuge	Ms. Substantial	Worker=REF(0xe3981324)
  9	Ms. Subsidy	Mr. Substantive	Worker=REF(0xe3981554)
  10	Ms. Subsidy	Ms. Substituent	Worker=REF(0xe3981554)
  11	nobody	Mr. Substitute
  12	Ms. Subterran	Mr. Substrate	Worker=REF(0xe3981394)
  13	Mr. Subrogation	Mr. Subterfuge	Worker=REF(0xe3980f48)
  14	Mr. Subsistent	Ms. Subterran	Worker=REF(0xe3981634)
  15	Ms. Substituent	Mr. Subtracter	Worker=REF(0xe3981784)
  16	Joshua	Mr. Subtrahend	Worker=REF(0xe3981e98)
  17	nobody	Ms. Subvert
  18	boss_name	name	boss

C<I<$at = ObjStore::Table2=REF(0xe39809b8)%> B<$db-E<gt>won>>

  Checking to see if Joshua has won...
    'Mr. Substitute' works for 'nobody' instead of you;
    You haven't won until everybody works for you.

C<I<$at = ObjStore::Table2=REF(0xe39809b8)%> B<ls $at-E<gt>array-E<gt>[11]>>

  [0] = Worker {
    name => 'Mr. Substitute',
  },

C<I<$at = ObjStore::Table2=REF(0xe39809b8)%> B<$at-E<gt>array-E<gt>[11]-E<gt>boss($db-E<gt>me)>>

  $fake1 = Worker {
    name => 'Joshua',
  },

C<I<$at = ObjStore::Table2=REF(0xe39809b8)%> B<$db-E<gt>won>>

  Checking to see if Joshua has won...
    'Ms. Subvert' works for 'nobody' instead of you;
    You haven't won until everybody works for you.

C<I<$at = ObjStore::Table2=REF(0xe39809b8)%> B<$db-E<gt>reset; ()>>

C<I<$at = ObjStore::Table2=REF(0xe39809b8)%> B<$db-E<gt>me-E<gt>name("Joshua")>>

  $fake1 = 'Joshua',

C<I<$at = ObjStore::Table2=REF(0xe39809b8)%> B<$db-E<gt>won>>

  Checking to see if Joshua has won...
    'Joshua' works for 'Ms. Subservient' instead of you;
    You haven't won until everybody works for you.

C<I<$at = ObjStore::Table2=REF(0xe39809b8)%> B<$db-E<gt>report>>

  index	boss	boss_name	name
  0	Worker=REF(0xe3981470)	Mr. Subsidiary	Joshua
  1	Worker=REF(0xe3981554)	Ms. Subrogation	Ms. Subliminal
  2	Worker=REF(0xe3981780)	Ms. Subsistent	Mr. Submersible
  3	Worker=REF(0xe3980c54)	Ms. Subliminal	Ms. Subrogation
  4	Worker=REF(0xe3981244)	Ms. Substantial	Ms. Subservient
  5	Worker=REF(0xe3981634)	Ms. Subservient	Mr. Subsidiary
  6	Worker=REF(0xe3981a9c)	Ms. Subterran	Mr. Subsidy
  7	Worker=REF(0xe3981a9c)	Ms. Subterran	Ms. Subsistent
  8	Worker=REF(0xe3981bec)	Mr. Subvert	Ms. Substantial
  9	Worker=REF(0xe3981b7c)	Ms. Subtrahend	Mr. Substantive
  10	Worker=REF(0xe3981864)	Mr. Submersible	Ms. Substituent
  11	Worker=REF(0xe3981b7c)	Ms. Subtrahend	Ms. Substitute
  12	Worker=REF(0xe3981a9c)	Ms. Subterran	Mr. Substrate
  13	Worker=REF(0xe3981394)	Ms. Substitute	Ms. Subterfuge
  14	Worker=REF(0xe3981244)	Ms. Substantial	Ms. Subterran
  15	Worker=REF(0xe3981470)	Mr. Subsidiary	Mr. Subtracter
  16	Worker=REF(0xe39819d0)	Mr. Substrate	Ms. Subtrahend
  17	Worker=REF(0xe3981634)	Ms. Subservient	Mr. Subvert
  18	boss	boss_name	name

C<I<$at = ObjStore::Table2=REF(0xe39809b8)%> B<cd array>>

C<I<$at = ObjStore::AV=REF(0xe3fd0000)%> B<ls>>

  $at = ObjStore::AV [
    Worker ...
    Worker ...
    Worker ...
    Worker ...
    Worker ...
    Worker ...
    Worker ...
    Worker ...
    Worker ...
    Worker ...
    Worker ...
    Worker ...
    Worker ...
    Worker ...
    Worker ...
    Worker ...
    Worker ...
    Worker ...
  ],

C<I<$at = ObjStore::AV=REF(0xe3fd0000)%> B<for (my $x=0; $at-E<gt>[$x]; $x++) { $at-E<gt>[$x]-E<gt>boss($db-E<gt>me) }>>

  $fake1 = 18,
  $fake2 = undef,

C<I<$at = ObjStore::AV=REF(0xe3fd0000)%> B<$db-E<gt>won>>

  Checking to see if Joshua has won...
    Congratuations!  Joshua wins!

C<I<$at = ObjStore::Table2=REF(0xe39809b8)%> B<ls>>

  $at = TABLE ObjStore::Table2 {
    array[18] of Worker ...
    indices: NAME;
  },

C<I<$at = ObjStore::Table2=REF(0xe39809b8)%> B<cd 3>>

C<I<$at = Worker=REF(0xe3981554)%> B<ls>>

  $at = Worker {
    boss => Worker ...
    name => 'Ms. Subrogation',
  },

C<I<$at = Worker=REF(0xe3981554)%> B<cd boss>>

C<I<$at = Worker=REF(0xe3980f48)%> B<ls>>

  $at = Worker {
    name => 'Joshua',
  },

C<I<$at = Worker=REF(0xe3980f48)%> B<>>

=head1 API REFERENCE

=cut

#------------------------------------------------------------
package Worker;
package ObjStore::Tutorial;
use ObjStore;
use ObjStore::Table2;
use base 'ObjStore::Table2::Database';

=head2 C<ObjStore::Tutorial>

 $db = ObjStore::Tutorial[/export2/os/tmp/tutor, update] {
  table => TABLE ObjStore::Table2 {
    array[21] of Worker {
      boss => Worker ...
      name => 'Mr. Subject',
    },
    indices: NAME;
  },
 },

=over 4

=cut

sub new {
    my $class = shift;
    my $db = $class->SUPER::new(@_);
    $db->reset;
    $db;
}

=item * $db->me

Returns yourself.

=cut

sub me { shift->array->[0] }

=item * $db->report

Print a CSV style report of who works for whom.

=cut

sub report {
    use ObjStore::CSV;
    print_csv(shift->array,
	      calc => {
		       'boss_name' => sub {
			   my $boss = shift->boss;
			   $boss? $boss->name : 'nobody'
		       },
		      },
	     );
    ()
}

=item * $db->won

Checks to see if you have won the tutorial.

=cut

sub won {
    my ($o, $me) = @_;
    $me ||= $o->array->[0];
    print "Checking to see if $me->{name} has won...\n";
    my $a = $o->array;
    my $win=1;
    my $loser;
    my $boss;
    for (my $x=0; $x < $a->_count; $x++) {
	$loser = $a->[$x];
	$boss = $loser->boss || 'nobody';
	my $loop=0;
	while ($loop < 100 && ref $boss && $boss->boss) {
	    die "Loop detected at $boss->{name}" if ++$loop > 100;
	    $boss = $boss->boss; 
	}
	next if $loser == $me && !ref($boss);
	if ($boss != $me) { $win=0; last }
    }
    if ($win) { print "  Congratuations!  $me->{name} wins!\n"; }
    else {
	$boss = $boss->name if ref $boss;
	print "  '$loser->{name}' works for '$boss' instead of you;\n";
	print "  You haven't won until everybody works for you.\n";
    }
    ()
}

=item * $db->reset

Resets the state of the tutorial.

=cut

sub reset {
    my ($db) = @_;
    my $t = $db->table;
    $t->new_index('Field', 'name');

    my $ar = $db->array;
    while ($ar->_count) { $ar->_Pop }
    for my $name (qw(subject subliminal submersible
		     subrogation subservient subsidiary subsidy subsistent
		     substantial substantive substituent substitute substrate
		     subterfuge subterran
		     subtracter subtrahend subvert)) {
	$ar->_Push(new Worker($db, (rand()>.5?"Mr. ":"Ms. "). ucfirst($name)));
    }
    for (my $x=0; $x < $ar->_count; $x++) {
	$ar->[$x]->boss($ar->[int(rand($ar->_count))]);
    }
    $t->rebuild_indices;
    $db;
}

=back

=cut

#------------------------------------------------------------
package Worker;
use ObjStore;
use base 'ObjStore::HV';

=head2 C<Worker>

 $at = Worker {
  boss => Worker ...
  name => 'Mr. Subject',
 },

=over 4

=cut

sub new {
    my ($class, $where, $name) = @_;
    my $o = $class->SUPER::new($where, 3);
    $o->{name} = $name;
    $o;
}

=item * $w->name([$new_name])

Returns the current name of the worker.  If $new_name is given,
does the re-assignment first.

=cut

sub name {
    my ($o, $nn) = @_;
    $o->{name} = $nn if @_ == 2;
    $o->{name}
}

=item * $w->boss([$new_boss])

Returns the current boss.  If a $new_boss is given, does the
re-assignment first.

=cut

sub boss {
    my ($o, $nb) = @_;
    if (@_ == 2) {
	if ($o == $nb) { delete $o->{boss}; }
	else           { $o->{boss} = $nb;  }
    }
    $o->{boss};
}

=back

=cut

1;

=head1 BUGS

Usage is a bit more cumbersome than I would like.  The interface will
change slightly as perl supports more overload-type features.

=head1 AUTHOR

Copyright (c) 1997 Joshua Nathaniel Pritikin.  All rights reserved.

This package is free software; you can redistribute it and/or modify
it under the same terms as perl itself.  This software is provided "as
is" without express or implied warranty.

=cut
