package ObjStore::Config;
require Exporter;
@ISA       = 'Exporter';
@EXPORT    = qw(&TMP_DBDIR);
@EXPORT_OK = qw(&SCHEMA_DBDIR);
%EXPORT_TAGS = (ALL => [@EXPORT, @EXPORT_OK]);


# Paths should have no trailing slash.
#
# Specify a directory for the application schema (and recompile):
# (override with $ENV{OSPERL_SCHEMA_DB})

sub SCHEMA_DBDIR() { 'greeqs092:/export/pinkie/schema' }


# Specify a directory for temporary databases (posh, perltest, etc):

sub TMP_DBDIR() { 'greeqs092:/export/pinkie/tmp' }


1;
