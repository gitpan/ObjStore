package ObjStore::Config;
require Exporter;
@ISA       = 'Exporter';
@EXPORT    = qw(&TMP_DBDIR);
@EXPORT_OK = qw(&SCHEMA_DBDIR);
%EXPORT_TAGS = (ALL => [@EXPORT, @EXPORT_OK]);


# Paths should have no trailing slash.
#
# Specify a directory for the application schema (and recompile):

sub SCHEMA_DBDIR() { '/opt/os/joshua' }


# Specify a directory for temporary databases (posh, osp_copy, etc):

sub TMP_DBDIR() { '/opt/os/tmp' }


1;
