#!/usr/bin/perl -w

package IO::String;
use strict;
use vars qw($VERSION @EXPORT @EXPORT_OK $AUTOLOAD @ISA);

use IO::Handle;
use IO::Seekable;

use English;
use Carp;

require Exporter;

@ISA = qw(IO::Handle IO::Seekable);

$VERSION = "1.00";

@EXPORT = @IO::Seekable::EXPORT;

sub new {
    my $type = shift;
    my $class = ref($type) || $type || "IO::String";
    @_ == 1
        or croak 'usage: new $class $string';
    my $fh = $class->SUPER::new();

    if (@_) {
#	print STDERR "opening string\n";
	$fh->open(@_)
            or return undef;
    }
    $fh;
}

sub member {
    my $self = shift;
    my $n = shift;
    my $array_ref;

    return undef unless $self;

    $array_ref = $*{$self};

#    print STDERR $array_ref->[$n], "\n";

    return \ $array_ref->[$n];
}

sub open {
    my $self = shift;
    my $string = shift;

    return undef unless defined $self;
    return undef unless defined $string;

    $*{$self} = [0, length $string, $string];

    return $self;
}

sub seek {
    my $self = shift or return undef;
    my $pos = shift;
    my $whence = shift;

    if ($whence == SEEK_SET) {
	$ {$self->member(0)} = $pos;
    } elsif ($whence == SEEK_CUR) {
	$ {$self->member(0)} += $pos;
    } elsif ($whence == SEEK_END) {
	$ {$self->member(0)} = $ {$self->member(1)} - $pos;
    }
    if ($ {$self->member(0)} < 0) {
	$ {$self->member(0)} = 0;
    }
    if ($ {$self->member(0)} > $ {$self->member(1)}) {
	$ {$self->member(0)} = $ {$self->member(1)};
    }
    
    return $self;
}

sub tell {
    my $self = shift;

    return $ {$self->member(0) };
}

sub close {
    my $self = shift;

    return undef unless defined $self;
    undef $*{$self};

    return $self;
}

sub fileno {
    my $self = shift;

    return undef;
}

sub getc {
    my $self = shift;
    my ($str_ref, $pos_ref, $len_ref);
    my $c;

    return undef unless defined $self;

    $pos_ref = $self->member(0);
    $len_ref = $self->member(1);
    $str_ref = $self->member(2);

#    printf STDERR "%d %d %s\n", $$pos_ref, $$len_ref, $$str_ref;

    # eof when try to read past end of string
    return undef if $self->eof;

    $c = substr($$str_ref, $$pos_ref, 1);
    $$pos_ref++;

    return $c;
}

sub gets {
    my $self = shift;
    my $str;
    my $retval;

    return undef unless defined $self;

    return undef if $self->eof;
    # reads until an eof or \n
    $str = '';
    while (defined ($retval = $self->getc) && $retval ne "\n") {
	$str .= $retval;
    }
    $str .= $retval if defined $retval;

    return $str;
}

sub eof {
    my $self = shift;
    my ($pos_ref, $len_ref);

    return undef unless defined $self;

    $pos_ref = $self->member(0);
    $len_ref = $self->member(1);

    return ($$pos_ref >= $$len_ref);
}

sub print {
    @_ or croak 'usage: $sh->print([ARGS])';
    my $self = shift;
    my $text;

    return undef unless defined $self;

    $text = join($, , @_);
    return undef unless defined $text;

    return $self->syswrite($text, length $text);
}

sub printf {
    @_ >= 2 or croak 'usage: $sh->printf(FMT, [ARGS])';
    my $self = shift;
    my ($pos_ref, $len_ref, $str_ref);
    my $text;

    return undef unless defined $self;

    $pos_ref = $self->member(0);
    $len_ref = $self->member(1);
    $str_ref = $self->member(2);

    $text = sprintf(@_);

    return $self->print($text);
}

sub getline {
    my $self = shift;

    return undef unless defined $self;
    $self->gets;
}

sub getlines {
    @_ == 1 or croak 'usage: $sh->getline()';
    wantarray or
        croak 'Can\'t call $sh->getlines in a scalar context, use $sh->getline';
    my $self = shift;
    my @lines = ();
    my $line;

    # read lines to the end of file and return 'em
    while (defined ($line = $self->getline)) {
	push(@lines, $line);
    }

    return @lines;
}

sub truncate {
    my $self = shift;
    my $len = shift;
    my ($pos_ref, $len_ref, $str_ref);

    return undef unless defined $self && defined $len;

    $pos_ref = $self->member(0);
    $len_ref = $self->member(1);
    $str_ref = $self->member(2);

    if ($$len_ref > $len) {
	$$len_ref = $len;
	$$str_ref = substr($$str_ref, 0, $len);
    }

    return $self;
}

sub read {
    my $self = shift;
    my $buf = $_[0];
    my $len = $_[1];
    my $offset = 0+$_[2];
    my ($pos_ref, $len_ref, $str_ref);
    my ($string, $length);

    return undef unless defined $self && defined $buf && defined $len;

    if ($self->eof) {
	return 0;
    }

    $pos_ref = $self->member(0);
    $len_ref = $self->member(1);
    $str_ref = $self->member(2);

    $string = substr($$str_ref, $$pos_ref, $len);
    $length = length $string;

    # increment position, checking for errors
    $$pos_ref += $length;

    $offset = 0 unless defined $offset;

    substr($buf, $offset, $length) = $string;
    return $length;
}

sub sysread {
    my $self = shift;

    return undef unless defined $self;
    $self->read(@_);
}

sub write {
    croak "write undefined for string handles";
}

sub syswrite {
    my $self = shift;
    my $buf = shift;
    my $len = shift;
    my $offset = shift;
    my ($pos_ref, $len_ref, $str_ref);
    my ($string, $length);

    return undef unless defined $self && defined $buf && defined $len;

    $offset = 0 unless defined $offset;

    $pos_ref = $self->member(0);
    $len_ref = $self->member(1);
    $str_ref = $self->member(2);

    $string = substr($buf, $offset, $len);
    $length = length $string;

    substr($$str_ref, $$pos_ref, $length) = $string;

    # increment position
    $$pos_ref += $length;
    $$len_ref = length $$str_ref;

    return $length;
}

sub stat {
    my $self = shift;
    my $len_ref;

    return undef unless defined $self;

    $len_ref = $self->member(1);

    return (
       "STRING",	# device number of filesystem
       scalar($self),	# inode number
       0777,		# permissions
       1,		# nlinks
       $EUID,		# owner uid
       $EGID,		# owner gid
       0,		# device identifier (na)
       $$len_ref,	# total size, in bytes
       0,		# last access time
       0,		# last mod time
       0,		# inode change time
       1,		# preferred block size
       undef,		# actual number of blocks allocated
	    );
}



1;
