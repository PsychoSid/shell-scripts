#!/usr/bin/perl -w
## ======================================================================================
## check_lsi
## --------------------------------------------------------------------------------------
use strict;
use warnings;
use Getopt::Long qw(:config no_ignore_case);

#
our $NOENCLOSURES = 0;
our $CONTROLLER   = 0;

# Header maps to parse logical and physical devices
our $LDMAP;
our @map_a = ('DG/VD', 'TYPE', 'State', 'Access', 'Consist', 'Cache', 'sCC', 'Size');
our @map_cc_a = ('DG/VD', 'TYPE', 'State', 'Access', 'Consist', 'Cache', 'Cac', 'sCC', 'Size');
our @pdmap_a =
    ('EID:Slt', 'DID', 'State', 'DG', 'Size', 'Intf', 'Med', 'SED', 'PI', 'SeSz', 'Model', 'Sp');

# Prints the name anmd the version of check_lsi_raid. If storcli is available,
# the version if it is printed also.
# @param storcli The path to storcli command utility
sub displayVersion {
  my $storcli = shift;
  if (defined($storcli)) {
    my @storcliVersion = `$storcli -v`;
    foreach my $line (@storcliVersion) {
      if ($line =~ /^\s+StorCli.*/) {
        $line =~ s/^\s+|\s+$//g;
        print $line;
      }
    }
    print "\n";
  }
  exit(STATE_OK);
}

# Checks if a storcli call was successfull, i.e. if the line 'Status = Sucess'
# is present in the command output.
# @param output The output of the storcli command as array
# @return 1 on success, 0 if not
sub checkCommandStatus {
  my @output = @{(shift)};
  foreach my $line (@output) {
    if ($line =~ /^Status/) {
      if ($line eq "Status = Success\n") {
        return 1;
      }
      else {
        return 0;
      }
    }
  }
}

# Shows the time the controller is using. Can be used to check if the
# controller number is a correct one.
# @param storcli The path to storcli command utility, followed by the controller
# number, e.g. 'storcli64 /c0'.
# @return 1 on success, 0 if not
sub getControllerTime {
  my $storcli = shift;
  my @output  = `$storcli show time`;
  return (checkCommandStatus(\@output));
}

# Get the status of the raid controller
# @param storcli The path to storcli command utility, followed by the controller
# number, e.g. 'storcli64 /c0'.
# @param logDevices If given, a list of desired logical device numbers
# @param commands_a An array to push the used command to
# @return A hash, each key a value of the raid controller info
sub getControllerInfo {
  my $storcli    = shift;
  my $commands_a = shift;
  my $command    = '';

  $storcli =~ /^(.*)\/c[0-9]+/;
  $command = $1 . 'adpallinfo a' . $CONTROLLER;
  push @{$commands_a}, $command;
  my @output = `$command`;
  if ($? >> 8 != 0) {
    print "Invalid StorCLI command! ($command)\n";
    exit(STATE_UNKNOWN);
  }
  my %foundController_h;
  foreach my $line (@output) {
    if ($line =~ /\:/) {
      my @lineVals = split(':', $line);
      $lineVals[0] =~ s/^\s+|\s+$//g;
      $lineVals[1] =~ s/^\s+|\s+$//g;
      $foundController_h{$lineVals[0]} = $lineVals[1];
    }
  }
  return \%foundController_h;
}

# Checks the status of the raid controller
# @param statusLevel_a The status level array, elem 0 is the current status,
# elem 1 the warning sensors, elem 2 the critical sensors, elem 3 the verbose
# information for the sensors.
# @param foundController The hash of controller infos, created by getControllerInfo
sub getControllerStatus {
  my @statusLevel_a   = @{(shift)};
  my %foundController = %{(shift)};
  my $status;
  foreach my $key (%foundController) {
    if ($key eq 'ROC temperature') {
      $foundController{$key} =~ /^([0-9]+\.?[0-9]+).*$/;
      if (defined($1)) {
        if (!(checkThreshs($1, $C_TEMP_CRITICAL))) {
          $status = 'Critical';
          push @{$statusLevel_a[2]}, 'ROC_Temperature';
        }
        elsif (!(checkThreshs($1, $C_TEMP_WARNING))) {
          $status = 'Warning';
          push @{$statusLevel_a[1]}, 'ROC_Temperature';
        }
        $statusLevel_a[3]->{'ROC_Temperature'} = $1;
      }
    }
    elsif ($key eq 'Degraded') {
      if ($foundController{$key} != 0) {
        $status = 'Warning';
        push @{$statusLevel_a[1]}, 'CTR_Degraded_drives';
        $statusLevel_a[3]->{'CTR_Degraded_drives'} = $foundController{$key};
      }
    }
    elsif ($key eq 'Offline') {
      if ($foundController{$key} != 0) {
        $status = 'Warning';
        push @{$statusLevel_a[1]}, 'CTR_Offline_drives';
        $statusLevel_a[3]->{'CTR_Offline_drives'} = $foundController{$key};
      }
    }
    elsif ($key eq 'Critical Disks') {
      if ($foundController{$key} != 0) {
        $status = 'Critical';
        push @{$statusLevel_a[2]}, 'CTR_Critical_disks';
        $statusLevel_a[3]->{'CTR_Critical_disks'} = $foundController{$key};
      }
    }
    elsif ($key eq 'Failed Disks') {
      if ($foundController{$key} != 0) {
        $status = 'Critical';
        push @{$statusLevel_a[2]}, 'CTR_Failed_disks';
        $statusLevel_a[3]->{'CTR_Failed_disks'} = $foundController{$key};
      }
    }
    elsif ($key eq 'Memory Correctable Errors') {
      if ($foundController{$key} != 0) {
        $status = 'Warning';
        push @{$statusLevel_a[1]}, 'CTR_Memory_correctable_errors';
        $statusLevel_a[3]->{'CTR_Memory_correctable_errors'} = $foundController{$key};
      }
    }
    elsif ($key eq 'Memory Uncorrectable Errors') {
      if ($foundController{$key} != 0) {
        $status = 'Critical';
        push @{$statusLevel_a[2]}, 'CTR_Memory_Uncorrectable_errors';
        $statusLevel_a[3]->{'CTR_Memory_Uncorrectable_errors'} = $foundController{$key};
      }
    }
  }
  if (defined($status)) {
    if ($status eq 'Warning') {
      if (${$statusLevel_a[0]} ne 'Critical') {
        ${$statusLevel_a[0]} = 'Warning';
      }
    }
    else {
      ${$statusLevel_a[0]} = 'Critical';
    }
    $statusLevel_a[3]->{'CTR_Status'} = $status;
  }
  else {
    $statusLevel_a[3]->{'CTR_Status'} = 'OK';
  }
}

