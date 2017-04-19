#!/usr/bin/perl

use Tie::File;
use File::Copy;

if ( @ARGV != 1 ) {
  print "Argument not passed to script.\n";
  exit 1;
}

$origfile = "/etc/passwd";
$copyfile = "/etc/passwd.prenetgroupadd";
$sudoorig = "/etc/sudoers";
$sudocopy = "/etc/sudoers.prenetgroupadd";

open my $fileh, '<', $origfile or die "Cannot open $origfile: $!";
my $netgroup = $ARGV[0];
my $foundit;
while ( <$fileh> ) {
  $foundit += /\+\@$netgroup/;
}

if ( $foundit ) {
  print "Already have this netgroup\n";
  exit 0;
}

close ( $fileh );

copy($origfile, $copyfile ) or die "Cannot make backup copy of $origfile will not continue.\n";

tie @pwfile, 'Tie::File', $origfile || die "Cannot open: $!\n";
$numpwrows = @pwfile;
$insertherepoint = $numpwrows - 1;
$newrec="+\@$ARGV[0]::::::\n";
splice @pwfile, $insertherepoint, 0, $newrec;
untie @pwfile;

copy($sudoorig, $sudocopy ) or die "Cannot make backup copy of $sudoorig will not continue.\n";

tie @sdfile, 'Tie::File', $sudoorig || die "Cannot open: $!\n";
$numsdrows = @sdfile;
$insertherepoint = $numsdrows - 1;
$newrec="+$ARGV[0]\tALL=NOPASSWD: /bin/rpm, /usr/bin/yum\n";
splice @sdfile, $insertherepoint, 0, $newrec;
untie @sdfile;
