use 5.00404;
use strict;
package ObjStore::Config;
require Exporter;
use vars qw(@ISA @EXPORT_OK $TMP_DBDIR $SCHEMA_DBDIR);
@ISA = 'Exporter';
@EXPORT_OK = qw($TMP_DBDIR $SCHEMA_DBDIR &DEBUG &SCHEMA_VERSION);

#---------------------------------------------------------------#

#   Enable support for ObjStore::debug() (not related to -DDEBUGGING)

sub DEBUG() { 1 };

#   Specify a directory for the schemas (and recompile):
#   (override with $ENV{OSPERL_SCHEMA_DBDIR})

$SCHEMA_DBDIR = 'elvis:/research/schema';

#   Specify a directory for temporary databases (posh, perltest, etc):

$TMP_DBDIR = 'elvis:/research/tmp';

#   Paths should not have a trailing slash.

#---------------------------------------------------------------#

sub API_VERSION() { '02' };     #do not edit!!
sub SCHEMA_VERSION() { '13' };  #do not edit!!

1;
