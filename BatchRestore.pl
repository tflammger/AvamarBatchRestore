#!/usr/bin/perl
#
# BatchRestore.pl
#
#----------------------------------------------------------------#
# Script restores a batch of servers using mccli and CSV file
# Author: Timothy Flammger 		<https://github.com/tflammger>
# Last Update: July 21, 2016
#----------------------------------------------------------------#

# process command flags with getopt
use Getopt::Std;
my %options=();
getopts("d:f:", \%options);

# -f config.file
if ($options{f}) {
	$configFile = $options{f};
} else {
	# if not set defaults to ./BatchRestore.csv
	$configFile = "./BatchRestore.csv";
}
# -d restore date in yyyy-mm-dd 
if ($options{d}) {
	if(IsValidDate($options{d})) {
		$restoreDate = $options{d};
		}
	else {
		# exit if date supplied is formatted incorrectly
		die("Invalid date supplied with -d: Expecting yyyy-mm-dd.\n");
		}
} else {
	# need to implement something here that defaults to "yesterday"
	die("Restore date is required, use -d yyyy-mm-dd\n");
}

# Initialize log files						
my $scriptStart = localtime();
my $logFile = "BatchRestore.log";      # primary logfile
my $errFile = "BatchRestoreError.log"; # Any Errors get dropped into here

open (LOGHANDLE, "+>> $logFile") or die "Can't open Logfile: $! \n";
open (ERRHANDLE, "+>> $errFile") or die "Can't open Errorlog: $! \n";
print LOGHANDLE "\n\n------------------------------------------------------------\n";
print LOGHANDLE "Starting BatchRestore using config file: $configFile at $scriptStart \n";
print LOGHANDLE "------------------------------------------------------------\n\n";
print ERRHANDLE "\n\n------------------------------------------------------------\n";
print ERRHANDLE "Starting BatchRestore.pl at $scriptStart \n";
print ERRHANDLE "------------------------------------------------------------\n\n";

# Process config file
open (CFGHANDLE, " < $configFile")
	or die("Couldn't find $configFile anywhere...Bye Bye $! \n");

my $count=1;	
while (<CFGHANDLE>) {
	chomp;
	s/#.*//;	# drop comments
	s/^\s+//;	# drop leading white space
	s/\s+$//;	# drop trailing whitespace
	next unless length; # go to the next line unless there is anything left to read
	# and if there is anthing left, read it and put it into array
	(@cmdArray) = split (/\s*,\s*/, $_, 7); # seperate records on comma
	push @cmdArray, $restoreDate; # add restore date from CLI
	# debug: die(print join(",", @cmdArray));

	# attempt to kick off restore job
	print LOGHANDLE localtime() . ": Attempting restore for $cmdArray[1] \n";	
	my $retVal = StartRestore (@cmdArray, $count);
	if ($retVal != 0) {
		# should do something more verbose with the error codes eventually
		# 10 = failed plugin lookup; 20 = failed label lookup; 30 = mccli restore cmd fail
		print "Something went wrong with restore of client $cmdArray[1] ... please check $errFile and $logFile for more info \n";
		print LOGHANDLE localtime() . ": Something went wrong with restore of client $cmdArray[1] \n";
	} else {
		print "Restore of client $cmdArray[1] started successfully. \n";
		print LOGHANDLE localtime() . ": Restore of client $cmdArray[1] started successfully. \n";
	}
	$count++;
}
# End Log
my $scriptEnd = localtime();
print "BatchRestore completed\n";
print LOGHANDLE "\n------------------------------------------------------------\n";
print LOGHANDLE "\tBatchRestore completed: $scriptEnd \n";
print LOGHANDLE "\tProcessed $count records \n";
print LOGHANDLE "------------------------------------------------------------\n\n";
print ERRHANDLE "\n------------------------------------------------------------\n";
print ERRHANDLE "\tBatchRestore completed: $scriptEnd \n";
print ERRHANDLE "------------------------------------------------------------\n\n";

# Clean-up file handles
close (CFGHANDLE);
close (LOGHANDLE);
close (ERRHANDLE);


#----------------------------------------------------------------#
# Subroutines
#----------------------------------------------------------------#

# --
# FindBackupLabel
# inputs source client, source domain for client, and date
# returns backup label for given date or 0 on error
# --
sub FindBackupLabel {
	my $domain = $_[0];
	my $client = $_[1];
	my $date = $_[2];
	my $backupLabel = 0;

	# debug: die("mccli backup show --domain=$domain --name=$client --before=$date --after=$date\n");
	open (my $mccli, "mccli backup show --domain=$domain --name=$client --before=$date --after=$date|") or die "Could not run command: $!\n";
	while (my $row = <$mccli>) {
		chomp $row;
		push (@tempArray, $row);
	}
	close ($mccli);	
	# debug: print join("\n", @tempArray);
		
	# the label we are looking for is in 4th row of the mccli output
	my @allData = split(" ", $tempArray[3]); 
	if ($allData[3] != 0){
		# Store the 3rd element from the 4th row of mccli output
		$backupLabel = $allData[3]; 
	} else {
		$backupLabel = 0;
	}
	undef @tempArray;
	
	# debug:	die("Label = $backupLabel\n");
	return ($backupLabel);
}

# --
# FindPlugin
# inputs source client, source domain for client, and date
# returns backup label for given date or 0 on error
# --
sub FindPlugin {
	my $domain = $_[0];
	my $client = $_[1];
	my $plugID = 0; 	
	# debug: die("mccli client show-plugins --domain=$domain --name=$client \n");

	# Lookup table for file system IDs we can restore
	my %lookup = qw(
		1001 => linux
		2001 => slorais 
		3001 => windows
		5001 => aix
	);
	
	# mccli output is a table where the frst 3 lines are header and command success message then a 2 column list of "ID Description"
	open (my $mccli, "mccli client show-plugins --domain=$domain --name=$client|") or die "Could not run command: $!\n";
	my $ln = 0;
	while (my $row = <$mccli>) {
		$ln++;
		next if ($ln <= 3);  # ignore first 3 junk lines
		chomp $row;
		push (@tempArray, $row);
	}
	close ($mccli);	
	# debug:	die(print join("\n", @tempArray));
	
	# id numbers are in column 1 followed by descriptions, we'll grab the ids and test for a known file system
	foreach $row (@tempArray) {
		my @allData = split(" ", $row); 
		# Store the ID  in element 0 of the mccli output row if it's in the lookup hash
		if (exists $lookup{$allData[0]}) {
			$plugID = $allData[0]; 
			last;
		} else {
			$plugID = 0;
		}
	}
	undef @tempArray;
	# debug:	die("plugin = $plugID\n");
	return ($plugID);
}

# --
# IsValidDate
# matches a date in yyyy-mm-dd format from 1900-01-01 through 2099-12-31
# returns 1 for correct date format or 0 on error
# Borrowed (and tweaked) from Jan Goyvaerts (http://www.regular-expressions.info/dates.html)
# --
sub IsValidDate {
  my $input = shift;
  if ($input =~ m!^((?:19|20)\d\d)[-](0[1-9]|1[012])[-](0[1-9]|[12][0-9]|3[01])$!) {
    # At this point, $1 holds the year, $2 the month and $3 the day of the date entered
    if ($3 == 31 and ($2 == 4 or $2 == 6 or $2 == 9 or $2 == 11)) {
      return 0; # 31st of a month with 30 days
    } elsif ($3 >= 30 and $2 == 2) {
      return 0; # February 30th or 31st
    } elsif ($2 == 2 and $3 == 29 and not ($1 % 4 == 0 and ($1 % 100 != 0 or $1 % 400 == 0))) {
      return 0; # February 29th outside a leap year
    } else {
      return 1; # Valid date
    }
  } else {
    return 0; # Not a date
  }
}

# --
# StartRestore
# Primary worker bee for formatting and issuing the mccli restore command
# inputs command array of variables from configuration file + restoreDate off CLI
# returns 0 on successful operation or error code if unable to start restore job
# --
sub StartRestore {
	my $srcDomain=$_[0]; 						# The Source Domain of the client
	my $srcClient=$_[1]; 						# The client name
	my $srcDirectory=$_[2]; 					# The direcotry to restore
	my $dstDomain=$_[3]; 						# the domain of the destination client
	my $dstClient=$_[4]; 						# the name of the destination client
	my $dstDirectory=$_[5]; 					# the restore target directory
	my $overwriteOpt=$_[6];						# keyword for existing-file-overwrite-option [always|modified|never|newest|newname]
	my $restoreDate=$_[7]; 						# the restore date (must be in format yyyy-mm-dd)
	my $counter=$_[8]; 							# A counter

	# Get plugin ID number: Will return 0 if we cannot find a file system plugin for the destination client
	my $pluginNumber = FindPlugin($dstDomain, $dstClient); 
	print LOGHANDLE localtime() . ": Searching for correct plugin to use... \n";
	if ($pluginNumber == 0) { 
		print ERRHANDLE localtime() . ": No client plugin ID found for destination ($dstDomain/$dstClient) \n";
		return (10);
	}
	print LOGHANDLE localtime() . ": located client ($dstDomain/$dstClient)... using plugin ($pluginNumber) for restore \n";
	
	# Get backup Label: Will return 0 if we cannot find a valid backup label for the source client
	print LOGHANDLE localtime() . ": Searching for label to restore $srcDomain/$srcClient to $date... \n";
	my $backupLabel = FindBackupLabel ($srcDomain, $srcClient, $restoreDate);
	if ($backupLabel == 0) { 
		print ERRHANDLE localtime() . ": No Backup found for $srcDomain/$srcClient on $date \n";
		return (20);
	}
	print LOGHANDLE localtime() . ": Found Backup Label ($backupLabel) for Client ($srcClient) on Date ($restoreDate) \n";
	
	# Do restore job
	print LOGHANDLE localtime() . ": Executing Restore from Client ($srcClient) to Destination ($dstClient) this will restore ($srcDirectory) to ($dstDirectory) \n";
	my $mccliReturn = system ("mccli backup restore --cmd=\"existing-file-overwrite-option=$overwriteOpt\" --cmd=\"deflateofficexml=false\" --domain=$srcDomain --name=$srcClient --data=$srcDirectory --labelNum=$backupLabel --dest-client-domain=$dstDomain --dest-client-name=$dstClient --dest-dir=$dstDirectory --plugin=$pluginNumber");

	# The mccli command below stattically uses the --cmd="deflateofficexml=false" option to avoid currupting MS Office XLM format files.
	# As of June 2016 EMC support position is that this option will cause no harm on restores that don't need it so we are using it globally here. 
	if ($mccliReturn != 0) {
		print ERRHANDLE localtime() . ": Execution of mccli backup restore failed for $srcClient ($mccliReturn) trying to execute: \n";
		print ERRHANDLE "\tmccli backup restore --cmd=\"existing-file-overwrite-option=$overwriteOpt\" --cmd=\"deflateofficexml=false\" --domain=$srcDomain --name=$srcClient --data=$srcDirectory --labelNum=$backupLabel --dest-client-domain=$dstDomain --dest-client-name=$dstClient --dest-dir=$dstDirectory --plugin=$pluginNumber \n";
		return (30); 
	}
	print LOGHANDLE localtime() . ": Restore job $counter from $restoreDate started successfully. ($srcDomain/$srcClient $srcDirectory ==> $dstDomain/$dstClient $dstDirectory using label $backupLabel)\n";
	return (0);
}
