# gee, shouldn't I test the synopsis?!

  use ObjStore ':ALL';

  my $db = ObjStore::open(&schema_dir . "/perltest.db", 0, 0666);

  try_update {
      my $top = $db->root('whiteboard') ||
                $db->root('whiteboard', new ObjStore::AV($db, 1000));
      for (my $x=1; $x < 10000; $x++) {
          my $z= $top->[$x];
          $top->[$x] ||= {
               id => $x,
               m1 => "I will not talk in ObjectStore/perl class.",
               m2 => "I will study the documentation before asking questions.",
          };
      }
      print "Very impressive.  I see you are already an expert.\n";
  };
