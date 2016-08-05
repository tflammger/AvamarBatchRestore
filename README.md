# AvamarBatchRestore
Perl script for EMC Avamar Grid shell that will automate mccli creation of restore jobs into a batch process fed by CSV data. 

Usage: 
1. Create a CSV batch list of job data the script will injest. (See BatchRestoreExample.csv)
2. Copy BatchRestore.pl and CSV data file to your Avamar Grid host using the admin secure shell. (WinSCP works well for this)
3. Execute script from CLI using ./BatchRestore.pl -f source-file.csv -d target-restore-date (restore date must be yyyy-mm-dd)

The perl script will attempt to use mccli to start a restore job for each source->target releationship defined in the CSV file. In this process the backup label for the supplied target date will be retrieved automatically for each line. The client file-system plugin will also be determined automatically. In regards to the client file system plugin the only ones currently being tested for are Windows, Linux, Solaris, and AIX (these are the only systems I have access to so they were the focus; adding others is however trivial by editing lookup table in FindPlugin sub).

