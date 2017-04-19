#!/usr/bin/perl -w
# ======================================================================================
# check_lsi_raid
# --------------------------------------------------------------------------------------
use strict;
use warnings;
use Data::Dumper;
use Getopt::Long qw(:config no_ignore_case);

# use File::Which;

our $VERBOSITY         = 0;
our $VERSION           = "2.1";
our $NAME              = "check_lsi_raid";
#our $C_TEMP_WARNING    = 80;
our $C_TEMP_WARNING    = 25;
our $C_TEMP_CRITICAL   = 40;
our $PD_TEMP_WARNING   = 70;
our $PD_TEMP_CRITICAL  = 85;
our ($IGNERR_M, $IGNERR_O, $IGNERR_P, $IGNERR_S, $IGNERR_B) = (0, 0, 0, 0, 0);
our $NOENCLOSURES = 0;
our $CONTROLLER   = 0;
our $check_mk_status;
our $check_mk_item;
our $check_mk_perf;
our $check_mk_text;

use constant {
  STATE_OK       => 0,
  STATE_WARNING  => 1,
  STATE_CRITICAL => 2,
  STATE_UNKNOWN  => 3,
};

# Header maps to parse logical and physical devices
our $LDMAP;
our @map_a = ('DG/VD', 'TYPE', 'State', 'Access', 'Consist', 'Cache', 'sCC', 'Size');
our @map_cc_a = ('DG/VD', 'TYPE', 'State', 'Access', 'Consist', 'Cache', 'Cac', 'sCC', 'Size');
our @pdmap_a =
    ('EID:Slt', 'DID', 'State', 'DG', 'Size', 'Intf', 'Med', 'SED', 'PI', 'SeSz', 'Model', 'Sp');

sub check_mk_output {
  if ("$_[0]" eq "Warning") {
    $check_mk_status = '1';
  } elsif ("$_[0]" eq "Critical") {
    $check_mk_status = '2';
  } else {
    $check_mk_status = '0';
  }
  $check_mk_item = $_[1];
  $check_mk_perf = $_[2];
  $check_mk_text = $_[3];
  print $check_mk_status . " " . $check_mk_item . " " . $check_mk_perf . " " . $check_mk_text . "\n";
}

sub openview_output {
  print "Openview stuff with opcagt goes here";
}

# Print command line usage to stdout.
sub displayUsage {
  print "Usage: \n";
  print "  [ -h | --help ]
    Display this help page\n";
  print "  [ -v | -vv | -vvv | --verbose ]
    Sets the verbosity level.
    No -v is the normal single line output for Nagios/Icinga, -v is a
    more detailed version but still usable in Nagios. -vv is a
    multiline output for debugging configuration errors or more";
  print "  [ -V --version ]
    Displays the plugin and, if available, the version if StorCLI.\n";
  print "  [ -C <num> | --controller <num> ]
    Specifies a controller number, defaults to 0.\n";
  print "  [ -EID <ids> | --enclosure <ids> ]
    Specifies one or more enclosure numbers, per default all enclosures. Takes either
    an integer as additional argument or a commaseperated list,
    e.g. '0,1,2'. With --noenclosures enclosures can be disabled.\n";
  print "  [ -LD <ids> | --logicaldevice <ids>]
    Specifies one or more logical devices, defaults to all. Takes either an
    integer as additional argument or a comma seperated list e.g. '0,1,2'.\n";
  print "  [ -PD <ids> | --physicaldevice <ids> ]
    Specifies one or more physical devices, defaults to all. Takes either an
    integer as additional argument or a comma seperated list e.g. '0,1,2'.\n";
  print "  [ -Tw <temp> | --temperature-warn <temp> ]
    Specifies the RAID controller temperature warning threshold, the default
    threshold is ${C_TEMP_WARNING}C.\n";
  print "  [ -Tc <temp> | --temperature-critical <temp> ]
    Specifies the RAID controller temperature critical threshold, the default
    threshold is ${C_TEMP_CRITICAL}C.\n";
  print "  [ -PDTw <temp> | --physicaldevicetemperature-warn <temp> ]
    Specifies the disk temperature warning threshold, the default threshold
    is ${PD_TEMP_WARNING}C.\n";
  print "  [ -PDTc <temp> | --physicaldevicetemperature-critical <temp> ]
    Specifies the disk temperature critical threshold, the default threshold
    is ${PD_TEMP_CRITICAL}C.\n";
  print "  [ -Im <count> | --ignore-media-errors <count> ]
    Specifies the warning threshold for media errors per disk, the default
    threshold is $IGNERR_M.\n";
  print "  [ -Io <count> | --ignore-other-errors <count> ]
    Specifies the warning threshold for media errors per disk, the default
    threshold is $IGNERR_O.\n";
  print "  [ -Ip <count> | --ignore-predictive-fail-count <count> ]
    Specifies the warning threshold for media errors per disk, the default
    threshold is $IGNERR_P.\n";
  print "  [ -Is <count> | --ignore-shield-counter <count> ]
    Specifies the warning threshold for media errors per disk, the default
    threshold is $IGNERR_S.\n";
  print "  [ -Ib <count> | --ignore-bbm-counter <count> ]
    Specifies the warning threshold for bbm errors per disk, the default
    threshold is $IGNERR_B.\n";
  print "  [ -p <path> | --path <path>]
    Specifies the path to StorCLI, per default uses /opt/MegaRAID/storcli/storcli64
    the StorCLI path.\n";
  print "  [ --noenclosures <0/1> ]
    Specifies if enclosures are present or not. 0 means enclosures are
    present (default), 1 states no enclosures are used (no 'eall' in
    storcli commands).\n"
}

# Displays a short Help text for the user
sub displayHelp {
  print $NAME. "\n";
  print "Plugin version: " . $VERSION . "\n";
  displayUsage();
  exit(STATE_OK);
}

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

# Checks if a storcli call was successfull, i.e. if the line 'Status = Success'
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
  my $text;
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

# Checks which logical devices are present for the given controller and parses
# the logical devices to a list of hashes. Each hash represents a logical device
# with its values from the output.
# @param storcli The path to storcli command utility, followed by the controller
# number, e.g. 'storcli64 /c0'.
# @param logDevices If given, a list of desired logical device numbers
# @param action The storcli action to check, 'all' or 'init'
# @param commands_a An array to push the used command to
# @return A list of hashes, each hash is one logical device. Check ldmap_a for valid
# hash keys.
sub getLogicalDevices {
  my $storcli    = shift;
  my @logDevices = @{(shift)};
  my $action     = shift;
  my $commands_a = shift;

  my $command = $storcli;
  if    (scalar(@logDevices) == 0) { $command .= "/vall"; }
  elsif (scalar(@logDevices) == 1) { $command .= "/v$logDevices[0]"; }
  else                             { $command .= "/v" . join(",", @logDevices); }
  $command .= " show $action";
  push @{$commands_a}, $command;

  my @output = `$command`;
  my @foundDevs;
  if (checkCommandStatus(\@output)) {
    if ($action eq "all") {
      my $currBlock;
      foreach my $line (@output) {
        my @splittedLine;
        if ($line =~ /^\/(c[0-9]*\/v[0-9]*).*/) {
          $currBlock = $1;
          next;
        }
        if (defined($currBlock)) {
          if ($line =~ /^DG\/VD TYPE.*/) {
            @splittedLine = split(' ', $line);
            if (scalar(@splittedLine) == 9) {
              $LDMAP = \@map_a;
            }
            if (scalar(@splittedLine) == 10) {
              $LDMAP = \@map_cc_a;
            }
          }
          if ($line =~ /^\d+\/\d+\s+\w+\d\s+\w+.*/) {
            @splittedLine = map { s/^\s*//; s/\s*$//; $_; } split(/\s+/, $line);
            my %lineValues_h;

            # The current block is the c0/v0 name
            $lineValues_h{'ld'} = $currBlock;
            for (my $i = 0; $i < @{$LDMAP}; $i++) {
              $lineValues_h{$LDMAP->[$i]} = $splittedLine[$i];
            }
            push @foundDevs, \%lineValues_h;
          }
        }
      }
    }
    elsif ($action eq "init") {
      foreach my $line (@output) {
        $line =~ s/^\s+|\s+$//g;    #trim line
        if ($line =~ /^([0-9]+)\s+INIT.*$/) {
          my $vdNum = 'c' . $CONTROLLER . '/v' . $1;
          if ($line !~ /Not in progress/i) {
            my %lineValues_h;
            my @vals = split('\s+', $line);
            $lineValues_h{'ld'}   = $vdNum;
            $lineValues_h{'init'} = $vals[2];
            push @foundDevs, \%lineValues_h;
          }
        }
      }
    }
  }
  else {
    print "Invalid StorCLI command! ($command)\n";
    exit(STATE_UNKNOWN);
  }
  return \@foundDevs;
}

# Checks the status of the logical devices.
# @param statusLevel_a The status level array, elem 0 is the current status,
# elem 1 the warning sensors, elem 2 the critical sensors, elem 3 the verbose
# information for the sensors.
# @param foundLDs The array of logical devices, created by getLogicalDevices
sub getLDStatus {
  my @statusLevel_a = @{(shift)};
  my @foundLDs      = @{(shift)};
  my $status;
  my $text;
  foreach my $LD (@foundLDs) {
    if (exists($LD->{'State'})) {
      if ($LD->{'State'} ne 'Optl') {
        $status = 'Critical';
        push @{$statusLevel_a[2]}, $LD->{'ld'} . '_State';
        $statusLevel_a[3]->{$LD->{'ld'} . '_State'} = $LD->{'State'};
        $text = $LD->{'State'};
      }
    }
    if (exists($LD->{'Consist'})) {
      if ($LD->{'Consist'} ne 'Yes' && $LD->{'TYPE'} ne 'Cac1') {
        $status = 'Warning';
        push @{$statusLevel_a[1]}, $LD->{'ld'} . '_Consist';
        $statusLevel_a[3]->{$LD->{'ld'} . '_Consist'} = $LD->{'Consist'};
        $text = $LD->{'Consist'};
      }
    }
    if (exists($LD->{'init'})) {
      $status = 'Warning';
      push @{$statusLevel_a[1]}, $LD->{'ld'} . '_Init';
      $statusLevel_a[3]->{$LD->{'ld'} . '_Init'} = $LD->{'init'};
      $text = $LD->{'init'};
    }
    if ($LD->{'State'} eq 'Optl') {
      $status = 'OK';
      push @{$statusLevel_a[2]}, $LD->{'ld'} . '_State';
      $statusLevel_a[3]->{$LD->{'ld'} . '_State'} = $LD->{'State'};
      $text = $LD->{'State'};
    }
    $check_mk_item = "LogicalDrive_" . $LD->{'ld'};
    $check_mk_perf = '-';
    $check_mk_text = "Logical Drive: " . $text;
    &check_mk_output($status, $check_mk_item, $check_mk_perf, $check_mk_text);
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
    $statusLevel_a[3]->{'LD_Status'} = $status;
  }
  else {
    if (!exists($statusLevel_a[3]->{'LD_Status'})) {
      $statusLevel_a[3]->{'LD_Status'} = 'OK';
    }
  }
}

# Checks which physical devices are present for the given controller and parses
# the physical devices to a list of hashes. Each hash represents a physical device
# with its values from the output.
# @param storcli The path to storcli command utility, followed by the controller
# number, e.g. 'storcli64 /c0'.
# @param physDevices If given, a list of desired physical device numbers
# @param action The storcli action to check, 'all', 'initialization' or 'rebuild'
# @param commands_a An array to push the used command to
# @return A list of hashes, each hash is one physical device. Check pdmap_a for valid
# hash keys.
sub getPhysicalDevices {
  my $storcli     = shift;
  my @enclosures  = @{(shift)};
  my @physDevices = @{(shift)};
  my $action      = shift;
  my $commands_a  = shift;

  my $command = $storcli;
  if (!$NOENCLOSURES) {
    if    (scalar(@enclosures) == 0) { $command .= "/eall"; }
    elsif (scalar(@enclosures) == 1) { $command .= "/e$enclosures[0]"; }
    else                             { $command .= "/e" . join(",", @enclosures); }
  }
  if    (scalar(@physDevices) == 0) { $command .= "/sall"; }
  elsif (scalar(@physDevices) == 1) { $command .= "/s$physDevices[0]"; }
  else                              { $command .= "/s" . join(",", @physDevices); }
  $command .= " show $action";
  push @{$commands_a}, $command;

  my @output = `$command`;
  my @foundDevs;
  if (checkCommandStatus(\@output)) {
    if ($action eq "all") {
      my $currBlock;
      my $line_ref;
      foreach my $line (@output) {
        my @splittedLine;
        if ($line =~ /^Drive \/(c[0-9]*\/e[0-9]*\/s[0-9]*) \:$/) {
          $currBlock = $1;
          $line_ref  = {};
          next;
        }
        if (defined($currBlock)) {

          # If a drive is not in a group, a - is at the DG column
          if ($line =~ /^\d+\:\d+\s+\d+\s+\w+\s+[0-9-F]+.*/) {
            @splittedLine = map { s/^\s*//; s/\s*$//; $_; } split(/\s+/, $line);

            # The current block is the c0/e252/s0 name
            $line_ref->{'pd'} = $currBlock;
            my $j = 0;
            for (my $i = 0; $i < @pdmap_a; $i++) {
              if ($pdmap_a[$i] eq 'Size') {
                my $size = $splittedLine[$j];
                if ($splittedLine[$j + 1] eq 'GB' || $splittedLine[$j + 1] eq 'TB') {
                  $size .= '' . $splittedLine[$j + 1];
                  $j++;
                }
                $line_ref->{$pdmap_a[$i]} = $size;
                $j++;
              }
              elsif ($pdmap_a[$i] eq 'Model') {
                my $model = $splittedLine[$j];

                # Model should be the next last element, j starts at 0
                if (($j + 2) != scalar(@splittedLine)) {
                  $model .= ' ' . $splittedLine[$j + 1];
                  $j++;
                }
                $line_ref->{$pdmap_a[$i]} = $model;
                $j++;
              }
              else {
                $line_ref->{$pdmap_a[$i]} = $splittedLine[$j];
                $j++;
              }
            }
          }
          if ($line
            =~ /^(Shield Counter|Media Error Count|Other Error Count|BBM Error Count|Drive Temperature|Predictive Failure Count|S\.M\.A\.R\.T alert flagged by drive)\s\=\s+(.*)$/
              )
          {
            $line_ref->{$1} = $2;
          }

          # If the last value is parsed, set up for the next device
          if (exists($line_ref->{'S.M.A.R.T alert flagged by drive'})) {
            push @foundDevs, $line_ref;
            undef $currBlock;
            undef $line_ref;
          }
        }
      }
    }
    elsif ($action eq 'rebuild' || $action eq 'initialization') {
      foreach my $line (@output) {
        $line =~ s/^\s+|\s+$//g;    #trim line
        if ($line =~ /^\/c$CONTROLLER\/.*/) {
          if ($line !~ /Not in progress/i) {
            my %lineValues_h;
            my @vals = split('\s+', $line);
            my $key;
            if ($action eq 'rebuild')        { $key = 'rebuild'; }
            if ($action eq 'initialization') { $key = 'init'; }
            $lineValues_h{'pd'} = substr($vals[0], 1);
            $lineValues_h{$key} = $vals[1];
            push @foundDevs, \%lineValues_h;
          }
        }
      }
    }
  }
  else {
    print "Invalid StorCLI command! ($command)\n";
    exit(STATE_UNKNOWN);
  }
  return \@foundDevs;
}

# Checks the status of the physical devices.
# @param statusLevel_a The status level array, elem 0 is the current status,
# elem 1 the warning sensors, elem 2 the critical sensors, elem 3 the vebose
# information for the sensors.
# @param foundPDs The array of physical devices, created by getPhysicalDevices
sub getPDStatus {
  my @statusLevel_a = @{(shift)};
  my @foundPDs      = @{(shift)};
  my $status;
  my $text;
  foreach my $PD (@foundPDs) {
    if (exists($PD->{'State'})) {
      if ( $PD->{'State'} ne 'Onln'
        && $PD->{'State'} ne 'UGood'
        && $PD->{'State'} ne 'GHS'
        && $PD->{'State'} ne 'DHS')
      {
        $status = 'Critical';
        push @{$statusLevel_a[2]}, $PD->{'pd'} . '_State';
        $statusLevel_a[3]->{$PD->{'pd'} . '_State'} = $PD->{'State'};
        $text = $PD->{'State'};
      } else {
        $status = 'OK';
        $text = "Drive OK";
      } 
      $check_mk_item = "PhysDriveState_" . $PD->{'pd'};
      $check_mk_perf = '-';
      $check_mk_text = "Physical Drive State: " . $text;
      &check_mk_output($status, $check_mk_item, $check_mk_perf, $check_mk_text);
    }
    if (exists($PD->{'Shield Counter'})) {
      if ($PD->{'Shield Counter'} > $IGNERR_S) {
        $status = 'Warning';
        push @{$statusLevel_a[1]}, $PD->{'pd'} . '_Shield_counter';
        $statusLevel_a[3]->{$PD->{'pd'} . '_Shield_counter'} = $PD->{'Shield Counter'};
        $text = $PD->{'Shield Counter'};
      }
    }
    if (exists($PD->{'Media Error Count'})) {
      if ($PD->{'Media Error Count'} > $IGNERR_M) {
        $status = 'Warning';
        push @{$statusLevel_a[1]}, $PD->{'pd'} . '_Media_error_count';
        $statusLevel_a[3]->{$PD->{'pd'} . '_Media_error_count'} = $PD->{'Media Error Count'};
        $text = $PD->{'Media Error Count'};
      }
    }
    if (exists($PD->{'Other Error Count'})) {
      if ($PD->{'Other Error Count'} > $IGNERR_O) {
        $status = 'Warning';
        push @{$statusLevel_a[1]}, $PD->{'pd'} . '_Other_error_count';
        $statusLevel_a[3]->{$PD->{'pd'} . '_Other_error_count'} = $PD->{'Other Error Count'};
        $text = $PD->{'Other Error Count'};
      }
    }
    if (exists($PD->{'BBM Error Count'})) {
      if ($PD->{'BBM Error Count'} > $IGNERR_B) {
        $status = 'Warning';
        push @{$statusLevel_a[1]}, $PD->{'pd'} . '_BBM_error_count';
        $statusLevel_a[3]->{$PD->{'pd'} . '_BBM_error_count'} = $PD->{'BBM Error Count'};
        $text = $PD->{'BBM Error Count'};
      }
    }
    if (exists($PD->{'Predictive Failure Count'})) {
      if ($PD->{'Predictive Failure Count'} > $IGNERR_P) {
        $status = 'Warning';
        push @{$statusLevel_a[1]}, $PD->{'pd'} . '_Predictive_failure_count';
        $statusLevel_a[3]->{$PD->{'pd'} . '_Predictive_failure_count'} =
            $PD->{'Predictive Failure Count'};
        $text = $PD->{'Predictive Failure Count'};
      }
    }
    if (exists($PD->{'S.M.A.R.T alert flagged by drive'})) {
      if ($PD->{'S.M.A.R.T alert flagged by drive'} ne 'No') {
        $status = 'Warning';
        push @{$statusLevel_a[1]}, $PD->{'pd'} . '_SMART_flag';
        $text = 'S.M.A.R.T alert flagged by drive';
      }
    }
    if (exists($PD->{'DG'})) {
      if ($PD->{'DG'} eq 'F') {
        $status = 'Warning';
        push @{$statusLevel_a[1]}, $PD->{'pd'} . '_DG';
        $statusLevel_a[3]->{$PD->{'pd'} . '_DG'} = $PD->{'DG'};
        $text = $PD->{'DG'};
      }
    }
    if (exists($PD->{'Drive Temperature'})) {
      my $temp = $PD->{'Drive Temperature'};
      if ($temp ne 'N/A' && $temp ne '0C (32.00 F)') {
        $temp =~ /^([0-9]+)C/;
        if (!(checkThreshs($1, $PD_TEMP_CRITICAL))) {
          $status = 'Critical';
          push @{$statusLevel_a[2]}, $PD->{'pd'} . '_Drive_Temperature';
        }
        elsif (!(checkThreshs($1, $PD_TEMP_WARNING))) {
          $status = 'Warning';
        } else {
          $status = 'OK';
        }
        $statusLevel_a[3]->{$PD->{'pd'} . '_Drive_Temperature'} = $1;
        $check_mk_item = "DriveTemp_" . $PD->{'pd'};
        $check_mk_perf = '-';
        $check_mk_text = "Drive Tempature: " . $temp;
        &check_mk_output($status, $check_mk_item, $check_mk_perf, $check_mk_text);
      }
    }
    if (exists($PD->{'init'})) {
      $status = 'Warning';
      push @{$statusLevel_a[1]}, $PD->{'pd'} . '_Init';
      $statusLevel_a[3]->{$PD->{'pd'} . '_Init'} = $PD->{'init'};
      $check_mk_text = "Drive Initialising";
    } elsif (exists($PD->{'rebuild'})) {
      $status = 'Warning';
      push @{$statusLevel_a[1]}, $PD->{'pd'} . '_Rebuild';
      $statusLevel_a[3]->{$PD->{'pd'} . '_Rebuild'} = $PD->{'rebuild'};
      $check_mk_text = "Drive Rebuilding";
    } else {
      push @{$statusLevel_a[1]}, $PD->{'pd'} . '_OK';
      $check_mk_text = "OK";
    }
    $check_mk_item = "PhysDriveItems_" . $PD->{'pd'};
    $check_mk_perf = '-';
    $check_mk_text = "Physical Drive Items: " . $check_mk_text;
    &check_mk_output($status, $check_mk_item, $check_mk_perf, $check_mk_text);
  }
}

# Checks if a given value is in a specified range, the range must follow the
# nagios development guidelines:
# http://nagiosplug.sourceforge.net/developer-guidelines.html#THRESHOLDFORMAT
# @param value The given value to check the pattern for
# @param pattern The pattern specifying the threshold range, e.g. '10:', '@10:20'
# @return 0 if the value is outside the range, 1 if the value satisfies the range
sub checkThreshs {
  my $value   = shift;
  my $pattern = shift;
  if ($pattern =~ /(^[0-9]+$)/) {
    if ($value < 0 || $value > $1) {
      return 0;
    }
  }
  elsif ($pattern =~ /(^[0-9]+)\:$/) {
    if ($value < $1) {
      return 0;
    }
  }
  elsif ($pattern =~ /^\~\:([0-9]+)$/) {
    if ($value > $1) {
      return 0;
    }
  }
  elsif ($pattern =~ /^([0-9]+)\:([0-9]+)$/) {
    if ($value < $1 || $value > $2) {
      return 0;
    }
  }
  elsif ($pattern =~ /^\@([0-9]+)\:([0-9]+)$/) {
    if ($value >= $1 and $value <= $2) {
      return 0;
    }
  }
  else {
    print "Invalid temperature parameter! ($pattern)\n";
    exit(STATE_UNKNOWN);
  }
  return 1;
}

# Get the status string as plugin output
# @param level The desired level to get the status string for. Either 'Warning'
# or 'Critical'.
# @param statusLevel_a The status level array, elem 0 is the current status,
# elem 1 the warning sensors, elem 2 the critical sensors, elem 3 the verbose
# information for the sensors, elem 4 the used storcli commands.
# @return The created status string
sub getStatusString {
  my $level         = shift;
  my @statusLevel_a = @{(shift)};
  my @sensors_a;
  my $status_str = "";
  if ($level eq "Warning") {
    @sensors_a = @{$statusLevel_a[1]};
  }
  if ($level eq "Critical") {
    @sensors_a = @{$statusLevel_a[2]};
  }

  #print Dumper(@statusLevel_a);
  # Add the controller parts only once
  my $parts = '';

  # level comes from the method call, not the real status level
  if ($level eq "Critical") {
    my @keys = ('CTR_Status', 'LD_Status', 'PD_Status');

    # Check which parts where checked
    foreach my $key (@keys) {
      $key =~ /^([A-Z]+)\_.*$/;
      my $part = $1;
      if (${$statusLevel_a[0]} eq 'OK') {
        if (exists($statusLevel_a[3]->{$key}) && $statusLevel_a[3]->{$key} eq 'OK') {
          $parts .= ", " unless $parts eq '';
          $parts .= $part;
        }
      }
      else {
        if (exists($statusLevel_a[3]->{$key}) && $statusLevel_a[3]->{$key} ne 'OK') {
          $parts .= ", " unless $parts eq '';
          $parts .= $part;
          $parts .= ' ' . substr($statusLevel_a[3]->{$key}, 0, 4);
        }
      }
    }
    $status_str .= '(';
    $status_str .= $parts unless !defined($parts);
    $status_str .= ')';
  }
  if ($level eq 'Critical') {
    $status_str .= ' ' unless !(@sensors_a);
  }
  if ($level eq 'Warning' && !@{$statusLevel_a[2]}) {
    $status_str .= ' ' unless !(@sensors_a);
  }
  if ($level eq "Warning" || $level eq "Critical") {
    if (@sensors_a) {

      # Print which sensors are Warn or Crit
      foreach my $sensor (@sensors_a) {
        $status_str .= "[" . $sensor . " = " . $level;
        if ($VERBOSITY) {
          if (exists($statusLevel_a[3]->{$sensor})) {
            $status_str .= " (" . $statusLevel_a[3]->{$sensor} . ")";
          }
        }
        $status_str .= "]";
      }
    }
  }
  return $status_str;
}

# Get the verbose string if a higher verbose level is used
# @param statusLevel_a The status level array, elem 0 is the current status,
# elem 1 the warning sensors, elem 2 the critical sensors, elem 3 the verbose
# information for the sensors, elem 4 the used storcli commands.
# @param controllerToCheck Controller parsed by getControllerInfo
# @param LDDevicesToCheck LDs parsed by getLogicalDevices
# @param LDInitToCheck LDs parsed by getLogicalDevices init
# @param PDDevicesToCheck PDs parsed by getPhysicalDevices
# @param PDInitToCheck PDs parsed by getPhysicalDevices init
# @param PDRebuildToCheck PDs parsed by getPhysicalDevices rebuild
# @return The created verbosity string
sub getVerboseString {
  my @statusLevel_a     = @{(shift)};
  my %controllerToCheck = %{(shift)};
  my @LDDevicesToCheck  = @{(shift)};
  my @LDInitToCheck     = @{(shift)};
  my @PDDevicesToCheck  = @{(shift)};
  my @PDInitToCheck     = @{(shift)};
  my @PDRebuildToCheck  = @{(shift)};
  my @sensors_a;
  my $verb_str;

  $verb_str .= "Used storcli commands:\n";
  foreach my $cmd (@{$statusLevel_a[4]}) {
    $verb_str .= '- ' . $cmd . "\n";
  }
  if (${$statusLevel_a[0]} eq 'Critical') {
    $verb_str .= "Critical sensors:\n";
    foreach my $sensor (@{$statusLevel_a[2]}) {
      $verb_str .= "\t- " . $sensor;
      if (exists($statusLevel_a[3]->{$sensor})) {
        $verb_str .= ' (' . $statusLevel_a[3]->{$sensor} . ')';
      }
      $verb_str .= "\n";
    }

  }
  if (${$statusLevel_a[0]} ne 'OK') {
    $verb_str .= "Warning sensors:\n";
    foreach my $sensor (@{$statusLevel_a[1]}) {
      $verb_str .= "\t- " . $sensor;
      if (exists($statusLevel_a[3]->{$sensor})) {
        $verb_str .= ' (' . $statusLevel_a[3]->{$sensor} . ')';
      }
      $verb_str .= "\n";
    }

  }
  if ($VERBOSITY == 3) {
    $verb_str .= "CTR information:\n";
    $verb_str .= "\t- " . $controllerToCheck{'Product Name'} . ":\n";
    $verb_str .= "\t\t- " . 'Serial No=' . $controllerToCheck{'Serial No'} . "\n";
    $verb_str .= "\t\t- " . 'FW Package Build=' . $controllerToCheck{'FW Package Build'} . "\n";
    $verb_str .= "\t\t- " . 'Mfg. Date=' . $controllerToCheck{'Mfg. Date'} . "\n";
    $verb_str .= "\t\t- " . 'Revision No=' . $controllerToCheck{'Revision No'} . "\n";
    $verb_str .= "\t\t- " . 'BIOS Version=' . $controllerToCheck{'BIOS Version'} . "\n";
    $verb_str .= "\t\t- " . 'FW Version=' . $controllerToCheck{'FW Version'} . "\n";
    $verb_str .= "\t\t- " . 'ROC temperature=' . $controllerToCheck{'ROC temperature'} . "\n";
    $verb_str .= "LD information:\n";
    foreach my $LD (@LDDevicesToCheck) {
      $verb_str .= "\t- " . $LD->{'ld'} . ":\n";
      foreach my $key (sort (keys(%{$LD}))) {
        $verb_str .= "\t\t- " . $key . '=' . $LD->{$key} . "\n";
      }
      foreach my $LDinit (@LDInitToCheck) {
        if ($LDinit->{'ld'} eq $LD->{'ld'}) {
          $verb_str .= "\t\t- init=" . $LDinit->{'init'} . "\n";
        }
      }
    }
    $verb_str .= "PD information:\n";
    foreach my $PD (@PDDevicesToCheck) {
      $verb_str .= "\t- " . $PD->{'pd'} . ":\n";
      foreach my $key (sort (keys(%{$PD}))) {
        $verb_str .= "\t\t- " . $key . '=' . $PD->{$key} . "\n";
      }
      foreach my $PDinit (@PDInitToCheck) {
        if ($PDinit->{'pd'} eq $PD->{'pd'}) {
          $verb_str .= "\t\t- init=" . $PDinit->{'init'} . "\n";
        }
      }
      foreach my $PDrebuild (@PDRebuildToCheck) {
        if ($PDrebuild->{'pd'} eq $PD->{'pd'}) {
          $verb_str .= "\t\t- rebuild=" . $PDrebuild->{'rebuild'} . "\n";
        }
      }
    }
  }
  return $verb_str;
}

# Get the performance string for the current check. The values are taken from
# the varbose hash in the status level array.
# @param statusLevel_a The current status level array
# @return The created performance string
sub getPerfString {
  my @statusLevel_a   = @{(shift)};
  my %verboseValues_h = %{$statusLevel_a[3]};
  my $perf_str;
  foreach my $key (sort (keys(%verboseValues_h))) {
    if ($key =~ /temperature/i) {
      $perf_str .= ' ' unless !defined($perf_str);
      $perf_str .= $key . '=' . $verboseValues_h{$key};
    }
    if ($key =~ /ROC_Temperature$/) {
      $perf_str .= ';' . $C_TEMP_WARNING . ';' . $C_TEMP_CRITICAL;
    }
    elsif ($key =~ /Drive_Temperature$/) {
      $perf_str .= ';' . $PD_TEMP_WARNING . ';' . $PD_TEMP_CRITICAL;
    }
  }
  return $perf_str;
}

MAIN: {
  my ($storcli, $version, $exitCode);

  # Create default sensor arrays and push them to status level
  my @statusLevel_a;
  my $status_str        = 'OK';
  my $warnings_a        = [];
  my $criticals_a       = [];
  my $verboseValues_h   = {};
  my $verboseCommands_a = [];
  push @statusLevel_a, \$status_str;
  push @statusLevel_a, $warnings_a;
  push @statusLevel_a, $criticals_a;
  push @statusLevel_a, $verboseValues_h;
  push @statusLevel_a, $verboseCommands_a;

  # Per default do not use a BBU
  my @enclosures;
  my @logDevices;
  my @physDevices;
  my $platform = $^O;

  if (
    !(GetOptions(
        'h|help'    => sub { displayHelp(); },
        'v|verbose' => sub { $VERBOSITY = 1 },
        'vv'        => sub { $VERBOSITY = 2 },
        'vvv'       => sub { $VERBOSITY = 3 },
        'V|version'                                 => \$version,
        'C|controller=i'                            => \$CONTROLLER,
        'EID|enclosure=s'                           => \@enclosures,
        'LD|logicaldevice=s'                        => \@logDevices,
        'PD|physicaldevice=s'                       => \@physDevices,
        'Tw|temperature-warn=s'                     => \$C_TEMP_WARNING,
        'Tc|temperature-critical=s'                 => \$C_TEMP_CRITICAL,
        'PDTw|physicaldevicetemperature-warn=s'     => \$PD_TEMP_WARNING,
        'PDTc|physicaldevicetemperature-critical=s' => \$PD_TEMP_CRITICAL,
        'Im|ignore-media-errors=i'                  => \$IGNERR_M,
        'Io|ignore-other-errors=i'                  => \$IGNERR_O,
        'Ip|ignore-predictive-fail-count=i'         => \$IGNERR_P,
        'Is|ignore-shield-counter=i'                => \$IGNERR_S,
        'Ib|ignore-bbm-counter=i'                   => \$IGNERR_B,
        'p|path=s'                                  => \$storcli,
        'noenclosures=i'                            => \$NOENCLOSURES,
      )
    )
      )
  {
    print $NAME . " Version: " . $VERSION . "\n";
    displayUsage();
    exit(STATE_UNKNOWN);
  }
  if (defined($version)) { print $NAME . "\nVersion: " . $VERSION . "\n"; }

  $storcli = '/opt/MegaRAID/storcli/storcli64';

  if (!defined($storcli)) {
    print "Error: cannot find storcli executable.\n";
    print "Ensure storcli is in your path, or use the '-p <storcli path>' switch!\n";
    exit(STATE_UNKNOWN);
  }

  # Print storcli version if available
  if (defined($version)) { displayVersion($storcli) }

  # Prepare storcli command
  $storcli .= " /c$CONTROLLER";

  # Check if the controller number can be used
  if (!getControllerTime($storcli)) {
    print "Error: invalid controller number, controller not found!\n";
    exit(STATE_UNKNOWN);
  }

  # Prepare command line arrays
  @enclosures  = split(/,/, join(',', @enclosures));
  @logDevices  = split(/,/, join(',', @logDevices));
  @physDevices = split(/,/, join(',', @physDevices));

  my $controllerToCheck = getControllerInfo($storcli, $verboseCommands_a);
  my $LDDevicesToCheck = getLogicalDevices($storcli, \@logDevices, 'all',  $verboseCommands_a);
  my $LDInitToCheck    = getLogicalDevices($storcli, \@logDevices, 'init', $verboseCommands_a);
  my $PDDevicesToCheck =
      getPhysicalDevices($storcli, \@enclosures, \@physDevices, 'all', $verboseCommands_a);
  my $PDInitToCheck = getPhysicalDevices($storcli, \@enclosures, \@physDevices, 'initialization',
    $verboseCommands_a);
  my $PDRebuildToCheck =
      getPhysicalDevices($storcli, \@enclosures, \@physDevices, 'rebuild', $verboseCommands_a);

  getControllerStatus(\@statusLevel_a, $controllerToCheck);
  getLDStatus(\@statusLevel_a, $LDDevicesToCheck);
  getLDStatus(\@statusLevel_a, $LDInitToCheck);
  getPDStatus(\@statusLevel_a, $PDDevicesToCheck);
  getPDStatus(\@statusLevel_a, $PDInitToCheck);
  getPDStatus(\@statusLevel_a, $PDRebuildToCheck);

  #print getStatusString("Critical", \@statusLevel_a);
  #print getStatusString("Warning",  \@statusLevel_a);
  #print getStatusString("OK",  \@statusLevel_a);
  #

  #my $perf_str = getPerfString(\@statusLevel_a);
  #if ($perf_str) {
  #print "|" . $perf_str;
    #}
  if ($VERBOSITY == 2 || $VERBOSITY == 3) {
    print "\n"
        . getVerboseString(
      \@statusLevel_a,   $controllerToCheck, $LDDevicesToCheck, $LDInitToCheck,
      $PDDevicesToCheck, $PDInitToCheck,     $PDRebuildToCheck
        );
  }

  # print Dumper(@statusLevel_a);
  $exitCode = STATE_OK;
  if (${$statusLevel_a[0]} eq "Critical") {
    #print "opc_msg: This thing is critical: " ;#. ${$statusLevel_a[1]};
    $exitCode = STATE_CRITICAL;
  }
  if (${$statusLevel_a[0]} eq "Warning") {
    #print "opc_msg: This thing is warning: " ;#. %{$statusLevel_a[1]};
    $exitCode = STATE_WARNING;
  }
  exit($exitCode);
}

