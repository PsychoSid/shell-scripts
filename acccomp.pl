#!/usr/bin/perl -- # vim: set ts=2 sw=2 et bg=dark tw=78:
#
# Comments:   Compare two passwd or group files and spot duplicates.
#

use strict;
use warnings;
use Getopt::Std;
use Data::Dumper;
use File::Basename;

my $progname = 'acccomp.pl';
my $opt_debug = 0;                      # debug. set with -D switch
my $os = $^O;                           # OS. Returns 'solaris' or 'linux'
my $user = $>;                          # EUID
my %opts;                               # Options passed on cmd line

##
## main
##

getopts('Dh', \%opts) || usage();
usage() if $opts{h};
$opt_debug = 1 if $opts{D};         # turn debugging on. obviously
my ($file1, $file2, $type1, $type2);
my $contents1 = {};                 # hashref1
my $contents2 = {};                 # hashref2
my $namedupes = [];                 # dupe name/gname array ref
my $iddupes = [];                   # dupe uid/gid array ref

# Need two files to compare
die "usage: $progname file1 file2\n" unless @ARGV == 2;

$file1 = $ARGV[0];
$file2 = $ARGV[1];
$type1 = filetype($file1);
$type2 = filetype($file2);

# If the file doesn't contain 4 or 7 fields, separated by colons, then
# 'filetype' will return a blank. It's probably a duff file.
if (! $type1 or ! $type2) {
  die "One of the files is not a passwd or group file. Please check\n";
}

# No point comparing apples and pears
unless ($type1 eq $type2) {
  die "The two files are different kinds. You need to compare like with like, i.e.\npasswd and passwd, group and group\n";
}

#$opt_debug and print "file1: $type1, file2: $type2\n";

# Load file into a hash
readfile($file1, $contents1);
readfile($file2, $contents2);

# if ($opt_debug) {
#   foreach my $id
#     (sort { ${$contents1}{$a} <=> ${$contents1}{$b} } keys %{$contents1}) {
#       print "$id:$contents1->{$id}\n";
#   }
#   foreach my $id
#     (sort { ${$contents2}{$a} <=> ${$contents2}{$b} } keys %{$contents2}) {
#       print "$id:$contents2->{$id}\n";
#   }
# }

# Do comparisons
finddupes($contents1, $contents2, $namedupes, $iddupes);

my (%idmapped1, %idmapped2);
# create new hashes of id => name, so we can print ID dupes later
while (my ($key,$value) = each %{$contents1}) {
  $idmapped1{@$value[0]} = $key;
}
while (my ($key,$value) = each %{$contents2}) {
  $idmapped2{@$value[0]} = $key;
}

$DB::single=1;

if ($opt_debug) {
  print "name dupes: ", scalar @$namedupes, "\n",
    "id dupes: ", scalar @$iddupes, "\n";
} else {
  print ',', basename($file1), ',', basename($file2), "\n";
  print "name,UID,UID,Comment,Comment\n";
  foreach my $namedup (@$namedupes) {
    print "$namedup,";
    print "@{$contents1->{$namedup}}[0],@{$contents2->{$namedup}}[0]";
    if ($type1 eq 'passwd') {
      print ",\"@{$contents1->{$namedup}}[1]\",";
      print "\"@{$contents2->{$namedup}}[1]\"\n";
    } else {
      print "\n";
    }
  }

  print "UID,name,name,Comment,Comment\n";
  foreach my $iddupe (@$iddupes) {
    print "$iddupe,";
    print "$idmapped1{$iddupe},$idmapped2{$iddupe}\n";
  }
}

exit;

##
## subs
##

# identify duplicates
sub finddupes
{
  # hashref, hashref, name duplicates, id duplicates
  my ($hr1, $hr2, $ndupes, $idupes) = @_;
  my @ids;        # somewhere to temporarily store user IDs from arrays in
                  # hash. If you get what I mean.

  foreach my $name (keys %{$hr1}) {
    push (@{$ndupes}, $name) if exists $hr2->{$name};
  }

  foreach my $val (values %{$hr2}) {
    push @ids, ${$val}[0];
  }

  # swap keys and values
  #my %rev2 = reverse %{$hr2};
  
  foreach my $id (values %{$hr1}) {
    push (@{$idupes}, ${$id}[0]) if exists $ids[${$id}[0]];
  }
}

# Read the file into a hash. We only want two fields each time anyway
sub readfile
{
  # $store is the hashref we'll put the stuff in. It's a hash of arrays.
  my ($file, $store) = @_;

  open (INPUT, "< $file") or die "Couldn't open $file: $!\n";

  while (my $line = <INPUT>) {
    next if $line =~ /^#/;
    my @record = split(/:/, $line, 6);
    my $id = $record[0];
    my $numeric = $record[2];
    my $gecos = $record[4] if $record[4];
    # We want to keep the gecos field from passwd to derive owners of service
    # accounts.
    push @{$store->{$id}}, $numeric, $gecos;
  }
  close INPUT;
}

# Is the file a passwd file, or a group file?
sub filetype
{
  my ($file) = @_;
  my @record;
  open (INPUT, "< $file") or die "Couldn't open $file: $!\n";

  while (my $line = <INPUT>) {
    next if $line =~ /^#/;
    @record = split(/:/, $line);
    last if @record > 3;
  }
  close INPUT;

  if (@record == 4) {
    return 'group';
  } elsif (@record == 7) {
    return 'passwd';
  } else {
    return;
  }
}
    

sub usage
{
  die <<EOF;
Compare two passwd or group files and find common names and IDs.

  usage: $progname [options] file1 file2
    -D          Debug. Doesn't perform actions, but prints information
    -h          Help. This text
EOF

}


__END__

=head1 NAME

B<COMMAND> - Some text

=head1 SYNOPSIS

B<COMMAND> B<switches> I<host>

=head1 DESCRIPTION

B<switches> blah blah

=head1 EXAMPLE

=cut


