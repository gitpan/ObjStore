# gee, shouldn't I test the synopsis?!

  use ObjStore;
  use ObjStore::Config;

  my $db = ObjStore::open(TMP_DBDIR . "/silly.db", 0, 0666);

  try_update {
      my $wb = $db->root('whiteboard', sub {new ObjStore::AV($db, 1001)});
      for (my $x=0; $x < 1000; $x++) {
          $wb->[$x] = {
               repetition => $x,
               msgs => ["I will not talk in ObjectStore/Perl class.",
                        "I will study the documentation before asking questions."]
          };
      }
  };
  print "Very impressive.  I see you are already an expert.\n";
