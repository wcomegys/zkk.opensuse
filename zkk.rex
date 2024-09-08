#!/usr/local/bin/regina
/* #! /usr/local/bin/regina */
/* zkk, The Infinite Improbability Suse DownLoad Shim for zypper */
/* Apache License, Version 2.0 */

call rxfuncadd 'sysloadfuncs', 'regutil', 'sysloadfuncs'
call sysloadfuncs

parse arg Params
Call_Count     = word(Params, 1)

numeric digits 16
/* Set for download speed output by aria2 */
Speed_Pad_Size_Int = 16
To_File_Bool = 1
Exiting_Bool = 0

Prg_Main_Name = 'zkk'
zkk_version = '1.0.0'

say 'This program is a multi-threaded download shim for zypper'
say 'For use on OpenSuse Tumbleweed and Leap'
say 'Log output not setup yet sending output to console'

select
  when Call_Count = '--version' then do
    say Prg_Main_Name || ' version ' || zkk_version
    exit
  end /* when do */
  when Call_Count = '-v'        then do
    say Prg_Main_Name || ' version ' || zkk_version
    exit
  end /* when do */
  otherwise nop
end /* select */

/* If first run get repositories, get patch listing, check file moves, otherwise skip */
Program_Name = '                 zkk'
Module       = '                                               Sanity_Checks'
Prg_Downloader_Name = 'ZK_downLoader'
First_Run_of_Init = 1
Log_File_Timer = 0

/* Start Set Defaults */
/* Clean up files created in tmp */
Cleanup_Temp_Files_After_Run = 'Y'
/* Min memory for shelling another download process */
Min_Memory_MB = 1024
/* Min disk for shelling another download process */
Min_Disk_MB = 1024
/* When trying to download needed patch listing try this many times before giving up */
Repo_Refresh_Retries_Int = 3
/* Valid download protocols if it is not included the repo is disabled */
Valid_Protocols = 'http,https'
/* I put this in to reduce messaging from ZK_downLoader for performance purposes */
ZK_downLoader_Debug = 0
/* How many download to do at once */
Max_Concurrent_Downloads_Int = 8
/* For Aria2 how long to wait for URL site connection */
Connect_Timeout_Sec = 15
/* For Aria2 how long to wait before trying a failed download again */
URL_Retry_Wait_Sec = 15
/* For Aria2 if average speed drops below this abort download */
Lowest_Speed_Limit_KB = 1
/* For Aria2 how many times to try the download before giving up */
Max_Retries_Per_Site_Int = 2
/* This is how many other sites to try before totaly giving up and not downloading the file */
Max_Total_Retries_Per_Loop_Int = 2
/* This controls how many repo URLs to use */
Repo_Sites_Int = 2
/* The scratch directory where the downloads go */
Work_Directory = '/tmp'
/* The cache directory where zypper uses the rpm files before installing them */
Cache_Directory = '/var/cache/zypp/packages/repo-update'
/* The repo directory where zypper uses for its downloads */
Repo_Directory = '/etc/zypp/repos.d'
/* After zkk completes its download run zypper dup to install updates */
Run_zypper_After_Download = 'N'
/* Run zypper with no confirm */
Run_zypper_with_No_Confirm = 'N'
/* Have zkk update download Run_zypper_Option || ' | tee /dev/tty'stats every T seconds */
/* Run_zypper_Option up dup is handled later after the Suse version is known */
Write_Zkk_Repos_Every_Sec = 300
/* Have zkk update download stats every C calls */
Write_Zkk_Repos_Every_Calls = 200
Save_Init_File_Time = ''
/* End Set Defaults */

/* Running as root? */
address system 'whoami' with output stem Return_Data.
if Return_Data.1 <> 'root' then do
   say '*** Fatal Error *** Not running as root exiting'
   exit
end /* if */

/* Check that rxstack is running */
 if Get_Process_Count('r[x]stack') = 0 then do
  say 'rxstack is used by all programs of this subsystem to push logging messages into a queue, so it does not run into file locking'
  say 'Please start rxstack -d and re-run the program'
  exit
 end /* if do */



/* Check for and Create log folder */
if length(stream('/var/log/zkk_download_shim', 'C', 'QUERY EXISTS')) = 0 then do
   address system 'mkdir -p  /var/log/zkk_download_shim'
   say 'Creating logging location directory /var/log/zkk_download_shim'
   address system 'chmod 755 /var/log/zkk_download_shim'
   say 'Setting permissions 755 on directory /var/log/zkk_download_shim'
  if length(stream('/var/log/zkk_download_shim', 'C', 'QUERY EXISTS')) = 0 then do
     say '*** Fatal Error *** Checking /var/log/zkk_download_shim directory does NOT exist'
	 say '*** Fatal Error *** Tried to create /var/log/zkk_download_shim directory, failed, exiting'
     exit
  end /* if */
end /* if */

/* trace(I?) */

Log_File = '/var/log/zkk_download_shim/zkk_' || date('S') || '_' || Time('N') || '.log'
Log_File = translate(Log_File,'_',':')
address system 'touch ' Log_File
Log_Data = 'To help manage log files please consider logrotate to help manage files under /var/log'
call Log_to_File

/* Checks to see if Regina REXX is installed */
/* need to check version 3.9.6, 3.9.1 from the zypper install gave segmentation faults */
address system 'which regina' with output stem Return_Data.
if Return_Data.0 = 0 then do
   say '*** Fatal Error *** Checking: Regina REXX does NOT exist, exiting'
   say 'zypper install Regina-REXX'
   Log_Data = '*** Fatal Error *** Checking: Regina REXX  does NOT exist, exiting'
   call Log_to_File
   exit
end /* then */
else do
   Log_Data = 'Checking: Regina REXX found in: ' Return_Data.1
   call Log_to_File
end /* else */
/* Need to check version of Regina REXX 3.9.6 >  */
address system 'regina --version' with output stem Return_Data.
Temp_Var = word(changestr('(', changestr('_', Return_Data.1,' '), ' '), 3)
if Return_Data.1 < '3.9.6' then do
   say 'Regina REXX version is less then 3.9.6 please upgrade with zypper install Regina-REXX'
   Log_Data = 'Regina REXX version is ' || Return_Data.1 || ' less then 3.9.6 please upgrade by downloading configure, make and make install'
   call Log_to_File
   exit
end /* if do */
else do
   Log_Data = 'regina --version returns: ' || Return_Data.1
   call Log_to_File
end /* else do */

/* Does /etc/zypp exist? */
if length(stream('/etc/zypp', 'C', 'QUERY EXISTS')) > 0 then do
   Log_Data = 'Normal Checking directory /etc/zypp does exist'
   call Log_to_File
end /* if do */
else do
   Log_Data = '*** Fatal Error *** Checking directory does NOT /etc/zypp exist'
   call Log_to_File
   exit
end /* else do */

/* Checks to see if aria2c is installed */
/* need to check version 1.36.0 */
address system 'which aria2c' with output stem Return_Data.
if Return_Data.0  = 0 then do
   say '*** Fatal Error *** Checking: aria2c does NOT exist, exiting'
   say 'zypper install arai2'
   Log_Data = '*** Fatal Error *** Checking: aria2c does NOT exist, exiting'
   call Log_to_File
   exit
end /* then */
else do
   Log_Data = 'Checking: aria2c found in: ' Return_Data.1
   call Log_to_File
end /* else */
address system 'aria2c --version' with output stem Return_Data.
if word(Return_Data.1, 3) < '1.36.0' then do
   say 'aria2c version is less then 1.36.0 please upgrade with zypper install aria2'
   Log_Data = 'arai2c version is ' || Return_Data.1 || ' less then 1.36.0 please upgrade with zypper install aria2'
   call Log_to_File
end /* if do */

/* Checks to see if rpm is installed */
address system 'which rpm' with output stem Return_Data.
if Return_Data.0  = 0 then do
   say '*** Fatal Error *** Checking: rpm does NOT exist, exiting'
   Log_Data = '*** Fatal Error *** Checking: rpm does NOT exist, exiting'
   call Log_to_File
   exit
end /* then */
else do
   Log_Data = 'Checking: rpm found in: ' Return_Data.1
   call Log_to_File
end /* else */

/* Checks to see if sha256sum is installed for ZK_downLoader */
address system 'which sha256sum' with output stem Return_Data.
if Return_Data.0  = 0 then do
   say '*** Fatal Error *** Checking: sha256sum does NOT exist, exiting'
   Log_Data = '*** Fatal Error *** Checking: sha256sum does NOT exist, exiting'
   call Log_to_File
   exit
end /* then */
else do
   Log_Data = 'Checking: sha256sum found in: ' Return_Data.1
   call Log_to_File
end /* else */

/* Checks to see if sha1sum is installed for ZK_downLoader */
address system 'which sha1sum' with output stem Return_Data.
if Return_Data.0  = 0 then do
   say '*** Fatal Error *** Checking: sha1sum does NOT exist, exiting'
   Log_Data = '*** Fatal Error *** Checking: sha1sum does NOT exist, exiting'
   call Log_to_File
   exit
end /* then */
else do
   Log_Data = 'Checking: sha1sum found in: ' Return_Data.1
   call Log_to_File
end /* else */

/* Checks to see if md5sum is installed for ZK_downLoader */
address system 'which md5sum' with output stem Return_Data.
if Return_Data.0  = 0 then do
   say '*** Fatal Error *** Checking: md5sum does NOT exist, exiting'
   Log_Data = '*** Fatal Error *** Checking: md5sum does NOT exist, exiting'
   call Log_to_File
   exit
end /* then */
else do
   Log_Data = 'Checking: md5sum found in: ' Return_Data.1
   call Log_to_File
end /* else */

/* Check for free memory program */
address system 'which free' with output stem Return_Data.
if Return_Data.0  = 0 then do
   say '*** Fatal Error *** Checking: free does NOT exist, exiting'
   Log_Data = '*** Fatal Error *** Checking: free does NOT exist, should be in base OS, exiting'
   call Log_to_File
   exit
end /* then */
else do
   Log_Data = 'Checking: free found in: ' Return_Data.1
   call Log_to_File
end /* else */

/* Check for zypper program */
address system 'which zypper' with output stem Return_Data.
if Return_Data.0  = 0 then do
   say '*** Fatal Error *** Checking: zypper does NOT exist, exiting'
   Log_Data = '*** Fatal Error *** Checking: zypper does NOT exist, should be in base OS, exiting'
   call Log_to_File
   exit
end /* then */
else do
   Log_Data = 'Checking: zypper found in: ' Return_Data.1
   call Log_to_File
end /* else */

/* Check for free diskspace program */
address system 'which df' with output stem Return_Data.
if Return_Data.0  = 0 then do
   say '*** Fatal Error *** Checking: df does NOT exist, exiting'
   Log_Data = '*** Fatal Error *** Checking: df does NOT exist, should be in base OS, exiting'
   call Log_to_File
   exit
end /* then */
else do
   Log_Data = 'Checking: df found in: ' Return_Data.1
   call Log_to_File
end /* else */

/* Check for download program ZDownLoad */
if length(stream('/usr/bin/' || Prg_Downloader_Name, 'C', 'QUERY EXISTS')) > 0 then do
   Log_Data = 'Normal Checking file /usr/bin/' || Prg_Downloader_Name || ' does exist'
   call Log_to_File
end /* if do */
else do
   say '*** Fatal Error *** Checking file /usr/bin/' || Prg_Downloader_Name || ' does NOT exist'
   Log_Data = '*** Fatal Error *** Checking file /usr/bin/' || Prg_Downloader_Name || ' does NOT exist'
   call Log_to_File
   Log_Data = '*** /usr/bin/' || Prg_Downloader_Name || ' should have been included in this file set'
   call Log_to_File
   exit
end /* else do */
address system Prg_Downloader_Name || ' --version' with output stem Return_Data.
if word(Return_Data.1, 3) < '1.0.0' then do
   say Prg_Downloader_Name || ' is less then 1.0.0 please upgrade'
   Log_Data = Prg_Downloader_Name || ' version is ' || Return_Data.1 || ' less then 1.0.0 please upgrade.'
   call Log_to_File
end /* if do */

if length(stream('/etc/zkk_download_shim', 'C', 'QUERY EXISTS')) > 0 then do
   Log_Data = 'Normal Checking directory /etc/zkk_download_shim does exist'
   call Log_to_File
end /* if do */
else do
   Log_Data = 'Directory /etc/zkk_download_shim directory does NOT exist, creating'
   call Log_to_File
   address system 'mkdir -p  /etc/zkk_download_shim'
   Log_Data = 'Setting permissions 755 on directory /etc/zkk_download_shim'
   call Log_to_File
/*      New_Init_File_Time = time('S', Config_File_Time, 'N') */
   address system 'chmod 755 /etc/zkk_download_shim'
  if length(stream('/etc/zkk_download_shim', 'C', 'QUERY EXISTS')) = 0 then do
   Log_Data = '*** Fatal Error *** Tried to create directory /etc/zkk_download_shim directory failed, exiting'
   call Log_to_File
   exit
 end /* if do */
end /* else do */

/* Create alias repo area */
if length(stream('/etc/zkk_download_shim/repos.d', 'C', 'QUERY EXISTS')) > 0 then do
   Log_Data = 'Normal Checking directory /etc/zkk_download_shim/repos.d does exist'
   call Log_to_File
end /* if do */
else do
   Log_Data = 'Directory /etc/zkk_download_shim directory/repos.d does NOT exist, creating'
   call Log_to_File
   address system 'mkdir -p  /etc/zkk_download_shim/repos.d'
   Log_Data = 'Setting permissions 755 on directory /etc/zkk_download_shim/repos.d'
   call Log_to_File
   address system 'chmod 755 /etc/zkk_download_shim/repos.d'
  if length(stream('/etc/zkk_download_shim/repos.d', 'C', 'QUERY EXISTS')) = 0 then do
   Log_Data = '*** Fatal Error *** Tried to create directory /etc/zkk_download_shim/repos.d directory failed, exiting'
   call Log_to_File
   exit
 end /* if do */
end /* else do */

call Check_Opensuse_Version

Module       = '                                               Sanity_Checks'

/* Check for configuration file if it does not exists write one out */
if length(stream('/etc/zkk_download_shim/zkk.conf', 'C', 'QUERY EXISTS')) > 0 then do
   Config_File = '/etc/zkk_download_shim/zkk.conf'
   Log_Data = 'Normal Checking /etc/zkk_download_shim/zkk.conf file does exist'
   call Log_to_File
end /* if do */
else do
   Config_File = '/etc/zkk_download_shim/zkk.conf'
   rc = lineout(Config_File, '# Config file for zkk zypper download shim')
   rc = lineout(Config_File, 'Cleanup_Temp_Files_After_Run Y')
   rc = lineout(Config_File, 'Min_Memory_MB 1024')
   rc = lineout(Config_File, 'Min_Disk_MB 1024')
   rc = lineout(Config_File, 'Repo_Refresh_Retries_Int 3')
   rc = lineout(Config_File, 'Valid_Protocols http,https')
   rc = lineout(Config_File, 'ZK_downLoader_Debug 0')
   rc = lineout(Config_File, 'Max_Concurrent_Downloads_Int 8')
   rc = lineout(Config_File, 'Connect_Timeout_Sec 15')
   rc = lineout(Config_File, 'URL_Retry_Wait_Sec 15')
   rc = lineout(Config_File, 'Lowest_Speed_Limit_KB 1')
   rc = lineout(Config_File, 'Max_Retries_Per_Site_Int 2')
   rc = lineout(Config_File, 'Max_Total_Retries_Per_Loop_Int 2')
   rc = lineout(Config_File, 'Repo_Sites_Int 2')
   rc = lineout(Config_File, 'Work_Directory /tmp')
   rc = lineout(Config_File, 'Cache_Directory /var/cache/zypp/packages/')
   rc = lineout(Config_File, 'Repo_Directory /etc/zypp/repos.d')
   rc = lineout(Config_File, 'Run_zypper_After_Download N')
   rc = lineout(Config_File, 'Run_zypper_with_No_Confirm N')
   rc = lineout(Config_File, 'Run_zypper_Clean_Deps N')
   if Opensuse_Distro_Name = 'Tumbleweed' then rc = lineout(Config_File, 'Run_zypper_Option dup')
   if Opensuse_Distro_Name = 'Leap' then rc = lineout(Config_File, 'Run_zypper_Option up')
   rc = lineout(Config_File, 'Write_Zkk_Repos_Every_Sec 300')
   rc = lineout(Config_File, 'Write_Zkk_Repos_Every_Calls 200')
   /* Close File */
   rc = lineout(Config_File)
   address system 'chmod 644 /etc/zkk_download_shim/zkk.conf'
  if length(stream('/etc/zkk_download_shim/zkk.conf', 'C', 'QUERY EXISTS')) = 0 then do
   Log_Data = '*** Fatal Error *** Tried to conf file /etc/zkk_download_shim/zkk.conf failed, exiting'
   call Log_to_File
   exit
  end /* if do */
   Log_Data = 'Created conf file /etc/zkk_download_shim/zkk.conf with defaults and set permissions to 644'
   call Log_to_File
end /* else do */

if Opensuse_Distro_Name = 'Tumbleweed' then Run_zypper_Option = 'dup'
if Opensuse_Distro_Name = 'Leap' then Run_zypper_Option = 'up'
New_Init_File_Time = 1
Save_Init_File_Time = 0
Cnt_Write_Zkk_Repos_Every_Calls = 0
Last_Write_Repos = time('T')

call Init

/* Set program to use global queue
say rxqueue('S','SESSION@127.0.0.1:5757')
SESSION
say rxqueue('G')
SESSION@127.0.0.1:5757
address system 'rxqueue /list'
address system 'rxqueue /queued'
*/
Parent_or_Child = fork()
if Parent_or_Child = 0 then do
   To_File_Bool = 0
   if Check_Queue('Thread_Rx_ZKK') = 0 then  rc = rxqueue('Create', 'Thread_Rx_ZKK@127.0.0.1:5757')
   rc = rxqueue('Set',    'Thread_Rx_ZKK@127.0.0.1:5757')
   if queued() > 0 then address system 'rxqueue /clear'
   if Check_Queue('Thread_Tx_ZKK') = 0 then  rc = rxqueue('Create', 'Thread_Tx_ZKK@127.0.0.1:5757')
   rc = rxqueue('Set',    'Thread_Tx_ZKK@127.0.0.1:5757')
   if queued() > 0 then address system 'rxqueue /clear'
   if Check_Queue('Thread_Log_ZKK') = 0 then rc = rxqueue('Create', 'Thread_Log_ZKK@127.0.0.1:5757')
   rc = rxqueue('Set',    'Thread_Log_ZKK@127.0.0.1:5757')
   if queued() > 0 then address system 'rxqueue /clear'
   call Download_Loop
end /* if do */
if Parent_or_Child > 0 then do
  rc = syssleep(0.1)
  rc = rxqueue('S','SESSION@127.0.0.1:5757')
  /* Create needed queues, The Z(PID) queues are created in ZK_downLoader */
  if Check_Queue('Main_Rx_ZKK') = 0 then  rc = rxqueue('Create', 'Main_Rx_ZKK@127.0.0.1:5757')
  rc = rxqueue('Set',    'Main_Rx_ZKK@127.0.0.1:5757')
  if queued() > 0 then address system 'rxqueue /clear'
  if Check_Queue('Main_Tx_ZKK') = 0 then  rc = rxqueue('Create', 'Main_Tx_ZKK@127.0.0.1:5757')
  rc = rxqueue('Set',    'Main_Tx_ZKK@127.0.0.1:5757')
  if queued() > 0 then address system 'rxqueue /clear'
  rc = rxqueue('Set',    'Thread_Log_ZKK@127.0.0.1:5757')
  call Log_Matrix
end /* if do */

do until Get_Process_Count('ownL[o]ad') = 0
   say 'Normal Waiting for background processes to complete ZDownLoad: ' Get_Process_Count('ownL[o]ad')
   Log_Data = 'Normal Waiting for background processes to complete ZDownLoad: ' Get_Process_Count('ownL[o]ad')
   call Log_to_File
   call Log_Matrix
   Module       = '                                                  Begin_Exit'
   sleep(1)
end /* until */

Module       = '                                                  Begin_Exit'
Exiting_Bool = 1
rc = cd(Saved_Directory)

Log_Data = 'Flush Log Queue'
call Log_to_File
/* Write out zkk repo information that is in memory before program exit */
call Write_Out_Zkk_Repos

rc = stream(Log_File, 'C', 'CLOSE')
address system 'cat ' || Work_Directory || '/' || 'Zypper_List_Updates.txt >> ' || Log_File
if upper(Cleanup_Temp_Files_After_Run) = 'Y' then rc = Remove_File(Work_Directory || '/' || 'Zypper_List_Updates.txt')

Module       = '                                                  Run_zypper'
/* Build zypper command */
select
  when upper(Run_zypper_After_Download) = 'Y' & upper(Run_zypper_with_No_Confirm) = 'N' then do
     Log_Data = 'Program information Run_zypper_After_Download, Running in interactive mode: ' || Run_zypper_After_Download
     call Log_to_File
     address system 'zypper ' || Run_zypper_Option || ' | tee /dev/tty' with output stem Zypp_Info.
    do Z = 1 to Zypp_Info.0
       Log_Data = Zypp_Info.Z
       call Log_to_File
    end /* do Z */
  end /* when */
  when upper(Run_zypper_After_Download) = 'Y' & upper(Run_zypper_with_No_Confirm) = 'Y' then do
     Log_Data = 'Program information Run_zypper_After_Download, Running in non interactive mode: ' || Run_zypper_After_Download
     call Log_to_File
     address system 'zypper --non-interactive ' || Run_zypper_Option || ' | tee /dev/tty' with output stem zypp_Info.
   do Z = 1 to Zypp_Info.0
      Log_Data = Zypp_Info.Z
      call Log_to_File
   end /* do Z */
  end /* when */
  otherwise do
    Log_Data = 'Program information Run_zypper_After_Download is N, skipping: ' || Run_zypper_After_Download
    call Log_to_File
    say 'Files downloaded to zypper cache please run zypper for Leap: zypper up or Tumbleweed: zypper dup'
    Log_Data = 'Files downloaded to zypper cache please run zypper for Leap: zypper up or Tumbleweed: zypper dup'
    call Log_to_File
  end /* otherwise */
end /* select */

Module       = '                                        Post zypper End_Exit'
say 'Log File: ' || Log_File
Log_Data = 'Normal End Program'
call Log_to_File
say 'Normal zkk End '
exit

/* Main Loop for downloading files */
/* trace(I?) */
Download_Loop:
do while (lines(Work_Directory || '/' || 'Zypper_List_Updates.txt') > 0)
/* trace(?I) */
Module       = '                                           Dispatch_Download'
/* Update last read config file time convert time to UTC numeric digits is expanded to 16 so it stay an int */
  Config_Date_Time = stream('/etc/zkk_download_shim/zkk.conf', 'C', 'QUERY TIMESTAMP')
  Config_File_Date = word(Config_Date_Time, 1)
  Config_File_Time = word(Config_Date_Time, 2)
  New_Init_File_Time = date('T', Config_File_Date, 'I') + time('S', Config_File_Time, 'N')
  if Save_Init_File_Time <> New_Init_File_Time then do
     Save_Init_File_Time = New_Init_File_Time
     Log_Data = 'Config file has new time stamp re-running Init, new Config_File UTC time: ' || New_Init_File_Time
     call Log_to_File
     call Init
     Module       = '                                           Dispatch_Download'
  end /* if do */

  /* Loop to wait if Zkk_Repo_Files need to be written uses rxstack for IPC communication */
/*   trace(?I) */
  rc = rxqueue('Set','Main_Tx_ZKK@127.0.0.1:5757')
  if Queued() > 0 then do
/*     trace(?I) */
    do until Queued() = 0 & Q_Tx_Flag = 0
       rc = rxqueue('Set','Main_Tx_ZKK@127.0.0.1:5757')
       Q_Tx_Flag = Queued()
       rc = rxqueue('Set', 'Main_Rx_ZKK@127.0.0.1:5757')
       if Q_Tx_Flag > 0 & Queued() = 0 then queue 'ACK'
       if Q_Tx_Flag = 0 then pull Junk_Var
       rc = syssleep(0.1)
    end /* do until */
  end /* if do  */
  rc = rxqueue('Set',    'Thread_Log_ZKK@127.0.0.1:5757')
  Process_Count = Get_Process_Count('ownL[o]ad')
  Free_Mem_MB = Get_Free_Mem_MB()
  Free_Disk_MB = Get_Free_Disk_MB(Cache_Directory)
  do while (Get_Free_Disk_MB(Cache_Directory) <  Min_Disk_MB) &   (Free_Mem_MB < Min_Memory_MB)
     say 'Insufficient disk or memory resources to continue: Memory ' || Get_Free_Mem_MB() || ' Expected ' || Free_Mem_MB || ' Disk ' || Get_Free_Disk_MB(Cache_Directory) || ' Expected ' Free_Disk_MB
     Log_Data = 'Insufficient disk or memory resources to continue: Memory ' || Get_Free_Mem_MB() || ' Expected ' || Free_Mem_MB || ' Disk ' || Get_Free_Disk_MB(Cache_Directory) || ' Expected ' Free_Disk_MB
     call Log_to_File
     sleep(10)
  end /* do while */
  Log_Data =  'Available Memory in MB: ' || Free_Mem_MB || ', Amount of free disk in MB: ' || Free_Disk_MB || ', Lines still need to read update file ' || lines(Work_Directory || '/' || 'Zypper_List_Updates.txt') || ', Number of Concurrent downloads ' || Process_Count
  call Log_to_File
  Num_To_Run = Max_Concurrent_Downloads_Int - Process_Count
  Run_Counter = 0
/* /*   trace(?I) */ */
  do while ((Num_To_Run => Run_Counter) & (lines(Work_Directory || '/' || 'Zypper_List_Updates.txt') > 0))
     /* trace(?I) */
     /* in column 1, S = Status, i = installed, v = updatable */
     In_Data = linein(Work_Directory || '/' || 'Zypper_List_Updates.txt')
     select
       when 'REFRESHING' = upper(word(In_Data, 1)) then nop
       when 'LOADING' = upper(word(In_Data, 1)) then nop
       when 'READING' = upper(word(In_Data, 1)) then nop
       when 'NO UPDATES FOUND.' = upper(strip(In_Data, 'B')) then do
            Log_Data = 'No Updates Found, Nothing Todo, Back to sleep ZZZs, Exiting.'
            say Log_Data
            call Log_to_File
       end
       when 'S' = upper(left(In_Data, 1)) & pos('|', In_Data) < 9 then nop
       when '-' = left(In_Data, 1) & pos('+', In_Data) > 0 & pos('-', In_Data, 9) > 0 then nop
       when 'V' = upper(left(In_Data, 1)) & pos('|', In_Data) < 9 then do
         Run_Counter += 1
         Cnt_Write_Zkk_Repos_Every_Calls += 1
         V = pos('|', In_Data) + 1
         B = pos('|', In_Data, V)
         Repo_Name   = strip(substr(In_Data, V, B - V, 'B'))
         Temp_Var      = strip(substr(In_Data, B + 1), 'B')
         Update_Module = word(Temp_Var, 1)
         Update_Version = word(Temp_Var, 5)
         Update_Archive = word(Temp_Var, 7)
         F = 0
         do until changestr('~', Repo_Box.1.F.4, ' ') = Repo_Name | F > Repo_Box.1.0.0
            F += 1
         end /* do until */
         if F <= Repo_Box.1.0.0 then do
            /* Build call to ZDownLoad #calls Repo_FileName  Update_Archive  Update_Module || '.' || Update_Version */
            Repo_Box.1.F.2 += 1
            Log_Data = Cnt_Write_Zkk_Repos_Every_Calls || ' of ' || Patch_Count.1 || ' ' || Repo_Box.1.F.1 || ' ' || Update_Archive ' ' || Update_Module || '-' || Update_Version || '.' || Update_Archive || '.rpm'
            call Log_to_File
            say Log_Data
            address system '/usr/bin/ZK_downLoader ' || Repo_Box.1.F.2 || ' ' || Repo_Box.1.F.1 || ' ' || Update_Archive ' ' || Update_Module || '-' || Update_Version || '.' || Update_Archive || '.rpm' || ' &'
         end /* if do */
         else do
            Log_Data = 'Repo not found for ' In_Data
            call Log_to_File
         end /* else do */
       end /* when do */
       otherwise do
         Log_Data = '** Warning ** Repo not found for: ' || In_Data || ', skipping'
         call Log_to_File
       end /* otherwise do */
     end /* select */
  end /* do while  */
end /* do while  */
/* End Program and flush Log_Data Queue */
exit
return

/* Library Routines */

/*
Reads the configuration file and check for sanity
*/
Init:
/* trace(?I) */
Module       = '                                                        Init'
/* Read Config File */
do while lines(Config_File) > 0
   In_Data = strip(linein(Config_File), 'B')
 if words(In_Data) => 2 then do
 select
   when ''                        = strip(In_Data, 'B') then nop
   when '#'                       = substr(strip(In_Data, 'B'), 1, 1) then nop
   when upper('CLEANUP_TEMP_FILES_AFTER_RUN')  = upper(word(In_Data, 1)) then do
     if upper(word(In_Data, 2)) = 'Y' | upper(word(In_Data, 2)) = 'N' then Cleanup_Temp_Files_After_Run = upper(word(In_Data, 2))
     else do
	    Log_Data = '** Warning ** Cleanup_Temp_Files_After_Run Y or N are valid: ' || word(In_Data, 2)
        call Log_to_File
     end /* else */
   end
   when upper('MIN_MEMORY_MB')  = upper(word(In_Data, 1)) then do
     if (datatype(word(In_Data, 2), W) = 1 & word(In_Data, 2) > 32) then Min_Memory_MB = word(In_Data, 2)
   end
   when upper('MIN_DISK_MB')  = upper(word(In_Data, 1)) then do
     if (datatype(word(In_Data, 2), W) = 1 & word(In_Data, 2) > 512) then Min_Disk_MB = word(In_Data, 2)
   end
   when upper('REPO_REFRESH_RETRIES_INT')  = upper(word(In_Data, 1)) then do
     if (datatype(word(In_Data, 2), W) = 1 & word(In_Data, 2) > 2) then Repo_Refresh_Retries_Int = word(In_Data, 2)
   end
   when upper('VALID_PROTOCOLS')  = upper(word(In_Data, 1)) then do
     Hold_Var = changestr(',', word(In_Data, 2) ,' ')
     Valid_Protocols.0 = 0
    do Z = 1 to words(Hold_Var)
      Temp_Var = strip(word(Hold_Var, Z), 'b')
      select
        when (pos('http', lower(Temp_Var)) > 0) & (length(Temp_Var) = 4) then do
          Valid_Protocols.0 += 1
          V = Valid_Protocols.0
          Valid_Protocols.V = 'http://'
        end /* when do */
        when pos('https', lower(Temp_Var)) > 0 then do
          Valid_Protocols.0 += 1
          V = Valid_Protocols.0
          Valid_Protocols.V = 'https://'
        end /* when do */
        when pos('ftp', lower(Temp_Var)) > 0 then do
          Valid_Protocols.0 += 1
          V = Valid_Protocols.0
          Valid_Protocols.V = 'ftp://'
        end /* when do */
        when pos('sftp', lower(Temp_Var)) > 0 then do
          Valid_Protocols.0 += 1
          V = Valid_Protocols.0
          Valid_Protocols.V = 'sftp://'
        end /* when do */
      end /* select */
    end /* do Z */
   end /* when */
   when upper('ZK_downLoader_Debug')  = upper(word(In_Data, 1)) then do
     if (datatype(word(In_Data, 2), W) = 1 & word(In_Data, 2) => 0 & word(In_Data, 2) <= 1) then ZK_downLoader_Debug = word(In_Data, 2)
     else do
        Log_Data = '** Warning ** ZK_downLoader_Debug is trying to be set out of bounds Int between 0 and 1 are valid: ' || word(In_Data, 2)
        call Log_to_File
        ZK_downLoader_Debug = 0
     end /* else */
   end
   when upper('MAX_CONCURRENT_DOWNLOADS_INT')  = upper(word(In_Data, 1)) then do
     if (datatype(word(In_Data, 2), W) = 1 & word(In_Data, 2) => 1 & word(In_Data, 2) <= 42) then Max_Concurrent_Downloads_Int = word(In_Data, 2)
     else do
        Log_Data = '** Warning ** Max_Concurrent_Downloads_Int is trying to be set out of bounds Int between 1 and 42 are valid: ' || word(In_Data, 2)
        call Log_to_File
        Max_Concurrent_Downloads_Int = 8
     end /* else */
   end
   when upper('CONNECT_TIMEOUT_SEC')  = upper(word(In_Data, 1)) then do
     if (datatype(word(In_Data, 2), W) = 1 & word(In_Data, 2) => 5 & word(In_Data, 2) <= 300) then Connect_Timeout_Sec = word(In_Data, 2)
     else do
	    Log_Data = '** Warning ** Connect_Timeout_Sec 5 to 300, 0 how long aria2 waits to connect to the URL, default is 15 seconds : ' || word(In_Data, 2)
        call Log_to_File
        Connect_Timeout_Sec = 15
    end /* else */
   end /* when */
   when upper('URL_RETRY_WAIT_SEC')  = upper(word(In_Data, 1)) then do
     if (datatype(word(In_Data, 2), W) = 1 & word(In_Data, 2) => 1 & word(In_Data, 2) <= 300) then URL_Retry_Wait_Sec = word(In_Data, 2)
     else do
	    Log_Data = '** Warning ** URL_Retry_Wait_Sec 1 to 300, 0 how long aria2 waits to retry a download to the URL, default is 15 seconds : ' || word(In_Data, 2)
        call Log_to_File
        URL_Retry_Wait_Sec = 15
    end /* else */
   end /* when */
   when upper('LOWEST_SPEED_LIMIT_KB')  = upper(word(In_Data, 1)) then do
     if (datatype(word(In_Data, 2), W) = 1 & word(In_Data, 2) => 1 & word(In_Data, 2) <= 1024) then Lowest_Speed_Limit_KB = word(In_Data, 2) || K
     else do
	    Log_Data = '** Warning ** Lowest_Speed_Limit_KB 1 to 1024, This is the slowest speed aria2 will stay connected in Kilo Bytes per Second : ' || word(In_Data, 2) || 'K'
        call Log_to_File
        Lowest_Speed_Limit_KB = 1K
    end /* else */
   end /* when */
   when upper('MAX_RETRIES_PER_SITE_INT')  = upper(word(In_Data, 1)) then do
     if (datatype(word(In_Data, 2), W) = 1 & word(In_Data, 2) => 1 & word(In_Data, 2) <= 16) then Max_Retries_Per_Site_Int = word(In_Data, 2)
     else do
        Log_Data = '** Warning ** Max_Retries_Per_Site_Int is trying to be set out of bounds Int between 1 and 16 are valid: ' || word(In_Data, 2)
        call Log_to_File
        Max_Retries_Per_Site_Int = 2
     end /* else */
   end
   when upper('MAX_TOTAL_RETRIES_PER_LOOP_INT')  = upper(word(In_Data, 1)) then do
     if (datatype(word(In_Data, 2), W) = 1 & word(In_Data, 2) => 1 & word(In_Data, 2) <= 16) then Max_Total_Retries_Per_Loop_Int = word(In_Data, 2)
     else do
	    Log_Data = '** Warning ** Max_Total_Retries_Per_Loop_Int is trying to be set out of bounds Int between 1 and 16 are valid: ' || word(In_Data, 2)
        call Log_to_File
        Max_Total_Retries_Per_Loop_Int = 2
    end /* else */
   end /* when */
   when upper('REPO_SITES_INT')  = upper(word(In_Data, 1)) then do
     if (datatype(word(In_Data, 2), W) = 1 & word(In_Data, 2) => 0 & word(In_Data, 2) <= 256) then Repo_Sites_Int = word(In_Data, 2)
     else do
	    Log_Data = '** Warning ** Repo_Sites_Int 0 to 256, 0 is training mode and will loop through all repo sites : ' || word(In_Data, 2)
        call Log_to_File
        Repo_Sites_Int = 5
    end /* else */
   end /* when */
   when upper('WORK_DIRECTORY') = upper(word(In_Data, 1)) then do
     Temp_Data = word(In_Data, 2)
	 if (length(Temp_Data)) <= 2 then do
	    Log_Data = '*** Fatal Error *** Work_Directory path is less then or equal to 2 characters exiting: ' || Temp_Data
        call Log_to_File
        exit
	 end /* if do */
	 if (left(Temp_Data,1) <> '/') then do
	    Log_Data = '*** Fatal Error *** Work_Directory path does not start with a / exiting: ' || Temp_Data
        call Log_to_File
        exit
	 end /* if do */
	 do while (right(Temp_Data, 1) = '/')
        Temp_Data = substr(Temp_Data, 1, length(Temp_Data) - 1)
	    Log_Data = 'House keeping Work_Directory path ends with a / removing: ' || Temp_Data
        call Log_to_File
	 end /* while */
	 if length(stream(Temp_Data, 'C', 'QUERY EXISTS')) = 0 then do
        Log_Data = '*** Fatal Error *** Work_Directory path does not exist, exiting: ' || Temp_Data
        call Log_to_File
	    exit
	 end /* if do */
	  Work_Directory = Temp_Data
   end /* when */
   when upper('CACHE_DIRECTORY')  = upper(word(In_Data, 1)) then do
     Temp_Data = word(In_Data, 2)
	 if (length(Temp_Data)) <= 2 then do
	    Log_Data = '*** Fatal Error *** Cache_Directory path is less then or equal to 2 characters exiting: ' || Temp_Data
        call Log_to_File
        exit
	 end /* if do */
	 if (left(Temp_Data,1) <> '/') then do
	    Log_Data = '*** Fatal Error *** Cache_Directory path does not start with a / exiting: ' || Temp_Data
        call Log_to_File
        exit
	 end /* if do */
	 do while (right(Temp_Data, 1) = '/')
        Temp_Data = substr(Temp_Data, 1, length(Temp_Data) - 1)
	    Log_Data = 'House keeping Cache_Directory path ends with a / removing: ' || Temp_Data
        call Log_to_File
	 end /* while */
	 if length(stream(Temp_Data, 'C', 'QUERY EXISTS')) = 0 then do
        Log_Data = '*** Fatal Error *** Cache_Directory path does not exist, exiting: ' || Temp_Data
        call Log_to_File
	    exit
	 end /* if do */
	  Cache_Directory = Temp_Data
   end /* when */
   when upper('REPO_DIRECTORY')  = upper(word(In_Data, 1)) then do
     Temp_Data = word(In_Data, 2)
	 if (length(Temp_Data)) <= 2 then do
	    Log_Data = '*** Fatal Error *** Repo_Directory path is less then or equal to 2 characters exiting: ' || Temp_Data
        call Log_to_File
        exit
	 end /* if do */
	 if (left(Temp_Data,1) <> '/') then do
	    Log_Data = '*** Fatal Error *** Repo_Directory path does not start with a / exiting: ' || Temp_Data
        call Log_to_File
        exit
	 end /* if do */
	 do while (right(Temp_Data, 1) = '/')
        Temp_Data = substr(Temp_Data, 1, length(Temp_Data) - 1)
	    Log_Data = 'House keeping Repo_Directory path ends with a / removing: ' || Temp_Data
        call Log_to_File
	 end /* while */
	 if length(stream(Temp_Data, 'C', 'QUERY EXISTS')) = 0 then do
        Log_Data = '*** Fatal Error *** Repo_Directory path does not exist, exiting: ' || Temp_Data
        call Log_to_File
	    exit
	 end /* if do */
	 rc = sysfiletree(Temp_Data || '/*.repo', Repo_Files.)
	 if (Repo_Files.0 = 0) then do
        Log_Data = '*** Fatal Error *** Repo_Directory does not contain any repo locations, exiting: ' || Temp_Data
        call Log_to_File
	    exit
	 end /* if do */
	  Repo_Directory = Temp_Data
   end /* when */
   when upper('RUN_ZYPPER_AFTER_DOWNLOAD')  = upper(word(In_Data, 1)) then do
        if upper(word(In_Data, 2)) = 'Y' | upper(word(In_Data, 2)) = 'N' then Run_zypper_After_Download = word(In_Data, 2)
        else do
           Log_Data = '** Warning ** Run_zypper_After_Download Y or N are valid: ' || word(In_Data, 2)
           call Log_to_File
        end /* else do */
   end /* when */
   when upper('RUN_ZYPPER_WITH_NO_CONFIRM')  = upper(word(In_Data, 1)) then do
        if upper(word(In_Data, 2)) = 'Y' | upper(word(In_Data, 2)) = 'N' then Run_zypper_with_No_Confirm = word(In_Data, 2)
        else do
	      Log_Data = '** Warning ** Run_zypper_with_No_Confirm Y or N are valid: ' || word(In_Data, 2)
          call Log_to_File
        end /* else */
   end /* when */
   when upper('RUN_ZYPPER_OPTION')  = upper(word(In_Data, 1)) then do
        if lower(word(In_Data, 2)) = 'dup' | lower(word(In_Data, 2)) = 'up' then Run_zypper_Option = lower(word(In_Data, 2))
        else do
	      Log_Data = '** Warning ** Run_zypper_Option dup or up are valid: ' || word(In_Data, 2)
          call Log_to_File
        end /* else */
        if Opensuse_Distro_Name = 'Tumbleweed' & Run_zypper_Option = 'up' then do
	      Log_Data = '** Warning ** zypper says Tumbleweed should be run with zypper dup, suggest correcting this in your zkk.conf file :' || Run_zypper_Option
          call Log_to_File
        end /* if do */
   end /* when */
   when upper('WRITE_ZKK_REPOS_EVERY_SEC')  = upper(word(In_Data, 1)) then do
     if (datatype(word(In_Data, 2), W) = 1 & word(In_Data, 2) => 30 & word(In_Data, 2) <= 1200) then Write_Zkk_Repos_Every_Sec = word(In_Data, 2)
     else do
	    Log_Data = '** Warning ** Write_Zkk_Repos_Every_Sec is trying to be set out of bounds Int between 30 and 1200 are valid: ' || word(In_Data, 2)
        call Log_to_File
        Write_Zkk_Repos_Every_Sec = 300
    end /* else */
   end /* when */
   when upper('WRITE_ZKK_REPOS_EVERY_CALLS')  = upper(word(In_Data, 1)) then do
     if (datatype(word(In_Data, 2), W) = 1 & word(In_Data, 2) => 100 & word(In_Data, 2) <= 2000) then Write_Zkk_Repos_Every_Calls = word(In_Data, 2)
     else do
	    Log_Data = '** Warning ** Write_Zkk_Repos_Every_Calls is trying to be set out of bounds Int between 10 and 1000 are valid: ' || word(In_Data, 2)
        call Log_to_File
        Write_Zkk_Repos_Every_Calls = 2
    end /* else */
   end /* when */
   when upper('RUN_ZYPPER_CLEAN_DEPS')  = upper(word(In_Data, 1)) then do
        if upper(word(In_Data, 2)) = 'Y' | upper(word(In_Data, 2)) = 'N' then Run_zypper_Clean_Deps = word(In_Data, 2)
        else do
	      Log_Data = '** Warning ** Run_zypper_Clean_Deps Y or N are valid: ' || word(In_Data, 2)
          call Log_to_File
        end /* else */
   end /* when */
   otherwise do
     Log_Data = "Don't know what this is: " || In_Data
     call Log_to_File
   end
 end /* select */
 end /* if do */
 else do
     Log_Data = 'Not at least 2 (two) words separated by a space: ' || In_Data
     call Log_to_File
 end /* else do */
end /* do while */

rc = stream(Config_File, 'C', 'CLOSE')

if First_Run_of_Init = 1 then do
   First_Run_of_Init = 0
   call Init_Patch_Box
   /*trace(?I)*/
   call Get_Patch_Listing
end /* if do */

Module       = '                                              Program Values'
Log_Data = '** Program Values ** zkk program version: ' || zkk_version
call Log_to_File
Log_Data = '** Program Values ** Cleanup_Temp_Files_After_Run: ' || Cleanup_Temp_Files_After_Run
call Log_to_File
Log_Data = '** Program Values ** Min_Memory_MB: ' || Min_Memory_MB
call Log_to_File
Log_Data = '** Program Values ** Min_Disk_MB: ' || Min_Disk_MB
call Log_to_File
Log_Data = '** Program Values ** Repo_Refresh_Retries_Int: ' || Repo_Refresh_Retries_Int
call Log_to_File
Log_Data = '** Program Values ** Number of Valid_Protocols: ' || Valid_Protocols.0
call Log_to_File
if Valid_Protocols.0 = 0 then do
   Log_Data = '*** Fatal Error *** Number of Valid_Protocols is 0 (Zero) at least 1 valid protocol is needed please add a text line like Valid_Protocols=http'
   call Log_to_File
   Log_Data = 'valid protocols are Valid_Protocols=http,https,ftp,sftp'
   call Log_to_File
   exit
end /* if do */
do V = 1 to Valid_Protocols.0
   Log_Data = 'Valid Protocols ' || Valid_Protocols.V
   call Log_to_File
end /* do V */
Log_Data = '* Program Values * ZK_downLoader_Debug: ' || ZK_downLoader_Debug
call Log_to_File
Log_Data = '* Program Values * Max_Concurrent_Downloads_Int: ' || Max_Concurrent_Downloads_Int
call Log_to_File
Log_Data = '* Program Values * Connect_Timeout_Sec: ' || Connect_Timeout_Sec
call Log_to_File
Log_Data = '* Program Values * URL_Retry_Wait_Sec: ' || URL_Retry_Wait_Sec
call Log_to_File
Log_Data = '* Program Values * Lowest_Speed_Limit_KB: ' || Lowest_Speed_Limit_KB
call Log_to_File
Log_Data = '* Program Values * Max_Retries_Per_Site_Int: ' || Max_Retries_Per_Site_Int
call Log_to_File
Log_Data = '* Program Values * Max_Total_Retries_Per_Loop_Int: ' || Max_Total_Retries_Per_Loop_Int
call Log_to_File
Log_Data = '* Program Values * Connect_Timeout_Sec: ' || Connect_Timeout_Sec
call Log_to_File
Log_Data = '* Program Values * Connect_Timeout_Sec: ' || Connect_Timeout_Sec
call Log_to_File
Log_Data = '* Program Values * Repo_Sites_Int: ' || Repo_Sites_Int
call Log_to_File
Log_Data = '* Program Values * Work_Directory: ' || Work_Directory
call Log_to_File
Log_Data = '* Program Values * Cache_Directory: ' || Cache_Directory
call Log_to_File
Log_Data = '* Program Values * Repo_Directory: ' || Repo_Directory
call Log_to_File
Log_Data = '* Program Values * Run_zypper_After_Download: ' || Run_zypper_After_Download
call Log_to_File
Log_Data = '* Program Values * Run_zypper_with_No_Confirm: ' || Run_zypper_with_No_Confirm
call Log_to_File
Log_Data = '* Program Values * Run_zypper_Option: ' || Run_zypper_Option
call Log_to_File
Log_Data = '* Program Values * Write_Zkk_Repos_Every_Calls: ' || Write_Zkk_Repos_Every_Calls
call Log_to_File
Log_Data = '* Program Values * Connect_Timeout_Sec: ' || Connect_Timeout_Sec
call Log_to_File

if Get_Free_Mem_MB() < Min_Memory_MB then do
   Log_Data = '*** Fatal Error *** Not enough free memory, either close some programs or decrease the required Min_Memory_MB setting in the configuration file, exiting: ' || Get_Free_Mem_MB()
   call Log_to_File
   exit
end /* if do */

if Get_Free_Disk_MB() <  Min_Disk_MB then do
   Log_Data = '*** Fatal Error *** Not enough free disk, either remove files or decrease the required Min_Disk_MB setting in the configuration file, exiting: ' || Get_Free_Disk_MB()
   call Log_to_File
   exit
end /* if do */
return

Check_Opensuse_Version:
Module       = '                                          Check_Suse_Version'
/* trace(?I) */
/* Read version file after Leap "version" Tumbleweed */
if length(stream('/etc/os-release', 'C', 'QUERY EXISTS')) = 0 then do
        Log_Data = '*** Fatal Error *** Can not open file /etc/os-release, exiting: ' || Temp_Data
        call Log_to_File
	    exit
end /* if do */
else do
  do while lines('/etc/os-release') > 0
    In_Data = changestr('"', changestr('=', linein('/etc/os-release'),' '), '')
   select
     when 'NAME' = upper(word(In_Data, 1)) & 'OPENSUSE' = upper(word(In_Data, 2)) then do
       Opensuse_Distro_Name = word(In_Data, 3)
     end /* when */
     when 'VERSION' = upper(word(In_Data, 1)) then Opensuse_Distro_Version = word(In_Data, 2)
     otherwise nop
   end /* select */
  end /* do */
  select
    when Opensuse_Distro_Name = 'Tumbleweed' then do
      Log_Data = 'Opensuse_Distro_Name is: ' || Opensuse_Distro_Name
      call Log_to_File
    end /* when */
    when Opensuse_Distro_Name = 'Leap' & datatype(Opensuse_Distro_Version, 'N') = 1 then do
      Log_Data = 'Opensuse_Distro_Name is: ' || Opensuse_Distro_Name || ' and version number is: ' || Opensuse_Distro_Version
      call Log_to_File
    end /* when */
    otherwise do
      Log_Data = '*** Fatal Error *** Can not find NAME and VERSION in file /etc/os-release'
      call Log_to_File
      Log_Data = '*** Fatal Error *** Supported versions are SUSE Leap and Tumbleweed, exiting'
      call Log_to_File
      exit
    end /* otherwise */
  end /* select */
end /* else */
return
/* Setup Repo matrix */
/*
File_Name, Name,
*/
/*
Setup Repo Matrix

Repo_Box.1.X.X Zypper Repo Information
Repo_Box.2.X.X Zkk Repo Information

Repo_FileName.1.X.1 +1
Repo_Access_Counter.1.X.2 + 1
Repo_Bytes_Downloaded.1.X.3 + 1
Repo_Name.1.X.4 + 1
baseurl.1.X.5 + 1
enabled.1.X.6 * 1
path.1.X.7
autorefresh.1.X.8
type.1.X.9
keeppackages.1.X.10

To be valid We need a (Repo_FileName + Repo_Name + baseurl) * enabled = 3
Repo_Box.2.X.Y Zkk Repo Information
*/
Init_Patch_Box:
Module       = '                                              Init_Patch_Box'
/* Get Repo file information */
rc = sysfiletree('/etc/zypp/repos.d/*.repo', Repo_Files., of)
Repo_Box.1.0.0 = 0
G = 1
Repo_Box.2.0.0 = 0
do I = 1 to Repo_Files.0
   /* say Repo_Files.I */
   Repo_Item_Counter = 1
   Temp = lastpos('/', Repo_Files.I) + 1
   Temp = substr(Repo_Files.I, Temp)
   Repo_Box.1.G.1 = left(Temp, lastpos('.repo', Temp) - 1)
   Repo_Box.1.G.2 = 0
   Repo_Box.1.G.3 = 0
   Repo_Box.1.G.0 = 10
  do while lines(Repo_Files.I, 'C') > 0
/*      trace(?I) */
     In_Data = translate(linein(Repo_Files.I), ' ', '=')
        Log_Data = 'Processing Repo Filename ' || Repo_Files.I
        call Log_to_File
    select
      when word(In_data, 1) = 'name' then do
        Repo_Box.1.G.4 = changestr(' ', subword(In_Data,2), '~')
        Repo_Item_Counter += 1
        Log_Data = "Repo name found " || Repo_Box.1.G.4
        call Log_to_File
      end /* when */
      when word(In_data, 1) = 'baseurl' then do
        Repo_Box.1.G.5 = subword(In_Data, 2)
        if length(Repo_Box.1.G.5) = lastpos('/', Repo_Box.1.G.5) then Repo_Box.1.G.5 = substr(Repo_Box.1.G.5, 1, length(Repo_Box.1.G.5) - 1)
        Repo_Item_Counter += 1
        Log_Data = "Repo_Baseurl " || Repo_Box.1.G.5
        call Log_to_File
      end /* when */
      when word(In_data, 1) = 'enabled' then do
        Repo_Box.1.G.6 = word(In_Data, 2)
        Repo_Box.1.G.6 = abs(sign(Repo_Box.1.G.6))
        Repo_Item_Counter += 1
        Log_Data = "Repo_Enabled " || Repo_Box.1.G.6
        call Log_to_File
      end /* when */
      when word(In_data, 1) = 'path' then do
        Repo_Box.1.G.7 =  word(In_Data, 2)
        Log_Data = "Repo_Path " || Repo_Box.1.G.7
        call Log_to_File
      end /* when */
      when word(In_data, 1) = 'autorefresh' then do
        Repo_Box.1.G.8 =  word(In_Data, 2)
        Log_Data = "Repo_Autofresh " || Repo_Box.1.G.8
        call Log_to_File
      end /* when */
      when word(In_data, 1) = 'type' then do
        Repo_Box.1.G.9 =  word(In_Data, 2)
        Log_Data = "Repo_Type " || Repo_Box.1.G.9
        call Log_to_File
      end /* when */
      when word(In_data, 1) = 'keeppackages' then do
        Repo_Box.1.G.10 =  word(In_Data, 2)
        Log_Data = "Repo_Keeppackages " || Repo_Box.1.G.10
        call Log_to_File
      end /* when */
      otherwise nop
    end /* select */
  end /* do while  */
/* trace(?I) */
  if Repo_Item_Counter => 4 then do
     call Init_zkk_Repo_Files
     G += 1
     Repo_Box.1.0.0 += 1
  end /* if do */
end /* do I */
return

Init_zkk_Repo_Files:
Module       = '                                         Init_zkk_Repo_Files'
/*
Enabled Avg_Download_Speed_KB baseurl # Successes #Failes Date Time Date Time ...
*/
Zkk_Repo_File_Name = '/etc/zkk_download_shim/repos.d/' || Repo_Box.1.G.1 ||  '.repo'
/* trace(?I) */
rc = sysfiletree(Zkk_Repo_File_Name, Zkk_Repo_Files., of)
if Zkk_Repo_Files.0 = 0 then do
   Log_Data = 'Creating zkk repo file ' || Repo_Box.1.G.1 || ' in directory /etc/zkk_download_shim/repos.d/'
   call Log_to_File
   Repo_Box.2.0.0 += 1
   Repo_Box.2.G.0 = 1
   Temp_baseurl = Repo_Box.1.G.5
   Temp_Enabled = Repo_Box.1.G.6
   Temp_Var = Pad_Left('0', Speed_Pad_Size_Int, '0')
   /* Check the baseurl has a valid protocol */
   Protocol_Check = 0
   do P = 1 to Valid_Protocols.0
      Protocol_Check += pos(Valid_Protocols.P, Temp_baseurl)
   end /* do P */
   Protocol_Check = sign(Protocol_Check)
   /* Check that Tumbleweed or Leap, and that Leap contains a $releasever if it does not have that will let zypper get it. */
   select
      when lower(Opensuse_Distro_Name) = 'tumbleweed' then do
        if (sign(pos('tumbleweed', lower(Temp_baseurl))) = 1) then do
           Compatibility_Check = 1
           Log_Data = 'Compatibility_Check: found tumbleweed in the baseurl string will be not disable :' || Temp_baseurl
           call Log_to_File
        end /* if do */
        else do
           Compatibility_Check = 0
           Log_Data = '** Warning ** Compatibility_Check: Did *NOT* find tumbleweed in the baseurl string will be disable :' || Temp_baseurl
           call Log_to_File
        end /* else do */
        end /* when */
        when lower(Opensuse_Distro_Name) = 'leap' then do
          if (sign(pos('leap', lower(Temp_baseurl))) = 1 & ((sign(pos('$releasever', lower(Temp_baseurl))) = 1) | (sign(pos(Opensuse_Distro_Version, lower(Temp_baseurl))) = 1))) then do
             Compatibility_Check = 1
             Log_Data = 'Compatibility_Check: found leap and either $releasever or the leap version number in the baseurl string will not be disable  :' || Temp_baseurl
             call Log_to_File
          end /* if do */
        else do
          Compatibility_Check = 0
          Log_Data = '** Warning ** Compatibility_Check: Did *NOT* find leap and either $releasever or the leap version number in the baseurl string will be disable :' || Temp_baseurl
          call Log_to_File
          end /* else do */
        end /* when */
        otherwise Compatibility_Check = 0
      end /* select */
      if (length(Temp_baseurl) > 15) & (Protocol_Check = 1) & (Compatibility_Check = 1) then do
         Log_Data = 'Found baseurl is longer than 15 and contains a valid protocol string :' || Temp_baseurl
         call Log_to_File
     end /* if do */
     else do
       Log_Data = 'baseurl is *NOT* longer than 15 or does *NOT* contain a valid protocol string, DISABLING repository line, enabled set to 0 :' ||  Temp_baseurl
       call Log_to_File
       Temp_Enabled = 0
     end /* else do */
   Repo_Box.2.G.1 =  Temp_Enabled || ' ' || Temp_Var || ' ' || Pad_Left('0', 7, '0') || ' ' || Pad_Left('0', 7, '0') || ' ' || Temp_baseurl
   rc = lineout(Zkk_Repo_File_Name , Repo_Box.2.G.1)
   /* Close the file */
   rc = lineout(Zkk_Repo_File_Name)
end /* if do */
else do
  Repo_Box.2.G.0 = 0
  do until lines(Zkk_Repo_File_Name) = 0 | Temp_Matrix = Repo_Box.1.G.5
     Temp_Extras = ''
     Temp_Var = linein(Zkk_Repo_File_Name)
     Log_Data = 'Repo File Name: ' || Zkk_Repo_File_Name || ' Line being processed ' || Temp_Var
     call Log_to_File
     if words(Temp_Var) => 5 then do
        Temp_Enabled        = word(Temp_Var, 1)
        Temp_Avg_Down_Speed = word(Temp_Var, 2)
        Temp_Successes      = word(Temp_Var, 3)
        Temp_Failures       = word(Temp_Var, 4)
        Temp_baseurl        = word(Temp_Var, 5)
        if length(Temp_baseurl) = lastpos('/', Temp_baseurl) then Temp_baseurl = substr(Temp_baseurl, 1, length(Temp_baseurl) - 1)
        if words(Temp_Var)> 5 then Temp_Extras = subword(Temp_Var, 6)
         if datatype(Temp_Enabled, 'B') = 1 then do
            Temp_Enabled = abs(sign(Temp_Enabled))
            Log_Data = 'Repo enabled 0 No 1 Yes: ' || Temp_Enabled
            call Log_to_File
         end /* if do */
         else do
            Log_Data = 'Repo enabled is not 0 or 1 (one) or is set to 0 resetting to 0: ' || Temp_Enabled
            call Log_to_File
            Temp_Enabled = 0
         end /* else do */
         if datatype(Temp_Avg_Down_Speed, 'W') = 1 then do
            Temp_Avg_Down_Speed = Pad_Left(Temp_Avg_Down_Speed, Speed_Pad_Size_Int, '0')
            Log_Data = 'Average Download Speed: ' || Temp_Avg_Down_Speed
            call Log_to_File
         end /* if do */
         else do
            Log_Data = 'Average Download Speed not an integer resetting to 0: ' || Temp_Avg_Down_Speed
            call Log_to_File
            Temp_Avg_Down_Speed = Pad_Left('0', Speed_Pad_Size_Int, '0')
         end /* else do */
         /* Check the baseurl has a valid protocol */
         Protocol_Check = 0
         do P = 1 to Valid_Protocols.0
            Protocol_Check += pos(Valid_Protocols.P, Temp_baseurl)
         end /* do P */
         Protocol_Check = sign(Protocol_Check)
         /* Check that Tumbleweed or Leap, and that Leap contains a $releasever if it does not have that will let zypper get it. */
           select
             when lower(Opensuse_Distro_Name) = 'tumbleweed' then do
               if (sign(pos('tumbleweed', lower(Temp_baseurl))) = 1) then do
                 Compatibility_Check = 1
                 Log_Data = 'Compatibility_Check: found tumbleweed in the baseurl string will not be disabled: ' || Temp_baseurl
                 call Log_to_File
               end /* if do */
               else do
                  Compatibility_Check = 0
                  Log_Data = '** Warning ** Compatibility_Check: Did *NOT* find tumbleweed in the baseurl string will be disabled: ' || Temp_baseurl
                  call Log_to_File
               end /* else do */
             end /* when */
             when lower(Opensuse_Distro_Name) = 'leap' then do
               if (sign(pos('leap', lower(Temp_baseurl))) = 1 & ((sign(pos('$releasever', lower(Temp_baseurl))) = 1) | (sign(pos(Opensuse_Distro_Version, lower(Temp_baseurl))) = 1))) then do
                  Compatibility_Check = 1
                  Log_Data = 'Compatibility_Check: found leap and either $releasever or the leap version number in the baseurl string will not be disable: ' || Temp_baseurl
                  call Log_to_File
               end /* if do */
               else do
                  Compatibility_Check = 0
                  Log_Data = '** Warning ** Compatibility_Check: Did *NOT* find leap and either $releasever or the leap version number in the baseurl string will be disabled: ' || Temp_baseurl
                  call Log_to_File
               end /* else do */
            end /* when */
            otherwise Compatibility_Check = 0
         end /* select */
         if (length(Temp_baseurl) > 15) & (Protocol_Check = 1) & (Compatibility_Check = 1) then do
            Log_Data = 'Found baseurl is longer than 15 and contains a valid protocol string: ' || Temp_baseurl
            call Log_to_File
         end /* if do */
         else do
            Log_Data = 'baseurl is *NOT* longer than 15 or does *NOT* contain a valid protocol string, DISABLING repository line, enabled set to 0 : ' ||  Temp_baseurl
            call Log_to_File
            Temp_Enabled = 0
         end /* else do */
         if datatype(Temp_Successes, 'W') = 1 then do
            Log_Data = 'Download Successes is an Integer: ' || Temp_Successes
            call Log_to_File
         end /* if do */
         else do
            Log_Data = 'Download Successes is *NOT* an integer resetting to 0: ' || Temp_Successes
            call Log_to_File
            Temp_Successes = 0
         end /* else do */
         if datatype(Temp_Failures, 'W') = 1 then do
            Log_Data = 'Download Failures is an Integer: ' || Temp_Failures
            call Log_to_File
         end /* if do */
         else do
            Log_Data = 'Download Failures is *NOT* an integer resetting to 0: ' || Temp_Failures
            call Log_to_File
            Temp_Failures = 0
         end /* else do */
         /* Build line after checking 6 on do not matter they will just roll off. */
         Repo_Box.2.G.0 += 1
         J = Repo_Box.2.G.0
         if words(Temp_Var)<= 5 then Repo_Box.2.G.J = Temp_Enabled || ' ' || Pad_Left(Temp_Avg_Down_Speed, Speed_Pad_Size_Int, '0') || ' ' || Pad_Left(Temp_Successes, 7, '0') || ' ' || Pad_Left(Temp_Failures, 7, '0') || ' ' || Temp_baseurl
         else Repo_Box.2.G.J = Temp_Enabled || ' ' || Pad_Left(Temp_Avg_Down_Speed, Speed_Pad_Size_Int, '0') || ' ' || Pad_Left(Temp_Successes, 7, '0') || ' ' || Pad_Left(Temp_Failures, 7, '0') || ' ' || Temp_baseurl || ' ' || Temp_Extras
       end /* if do */
     else do
       Log_Data = ' '
       call Log_to_File
       select
         when words(Temp_Var) = 0 then nop
         when words(Temp_Var) = 1 then do
           Temp_Var_B = Pad_Left('0', Speed_Pad_Size_Int, '0')
           Repo_Box.2.G.0 += 1
           J = Repo_Box.2.G.0
           Repo_Box.2.G.J = '0 ' || Temp_Var_B
         end /* when */
         when words(Temp_Var) = 2 then do
            Temp_Var_B = Pad_Left('0', Speed_Pad_Size_Int, '0')
            Repo_Box.2.G.0 += 1
            J = Repo_Box.2.G.0
            Repo_Box.2.G.J = '0 ' || Temp_Var_B
         end /* when */
         when words(Temp_Var) > 2 then do
            Temp_Var_B = Pad_Left('0', Speed_Pad_Size_Int, '0')
            Repo_Box.2.G.0 += 1
            J = Repo_Box.2.G.0
            Repo_Box.2.G.J = '0 ' || Temp_Var_B || subword(Temp_Var,3)
         end /* when */
         otherwise nop
       end /* select */
    end /* else do */
  end /* do until */
end /* else do */
return

/*
  Set up Repo_Box now that we have the information
*/

Get_Patch_Listing:
Module       = '                                           Get_Patch_Listing'
Repo_Refresh_Retries_Cnt = 0
/* trace(?I) */
do while Get_Process_Count('p[a]ckagekitd') > 0
  Pkiit_ID = Get_Process_ID('p[a]ckagekitd')
  if (Pkiit_ID <> 'NA') then kill -9 Pkiit_ID
end /* while */
  Log_Data = 'Get needed patch listing from zypper '
  call Log_to_File
  Log_Data = 'Checking for old patch listing file ' || Work_Directory || '/' || 'Zypper_List_Updates.txt'
  call Log_to_File
if length(stream(Work_Directory || '/' || 'Zypper_List_Updates.txt', 'C', 'QUERY EXISTS')) > 0 then do
   Log_Data = 'Old Patch file exists removing: ' || Work_Directory || '/' || 'Zypper_List_Updates.txt'
   call Log_to_File
   address system 'rm ' || Work_Directory || '/' || 'Zypper_List_Updates.txt'
   if length(stream(Work_Directory || '/' || 'Zypper_List_Updates.txt', 'C', 'QUERY EXISTS')) > 0 then do
      Log_Data = 'Old Patch file still exists removing failed exiting: ' || Work_Directory || '/' || 'Zypper_List_Updates.txt'
      call Log_to_File
      exit
   end /* if do */
end /* if do */
/* */

say 'Sometimes zypper refresh get stuck, give it 5 minutes, if you think it is stuck you can (Control C) and try re-running this program zkk'
say 'If zypper reports a refresh failure zkk will try ' || Repo_Refresh_Retries_Int || ' more times and then abort this program, this setting can be modified in the zkk configuration file'
Log_Data = 'Sometimes zypper refresh get stuck, give it 5 minutes, if you think it is stuck you can (Control C) and try re-running this program zkk'
call Log_to_File
call Log_to_File
Temp_Repo_Refresh_Retries = 0
do until ((Check_Repos.0 <= Temp_Count_Refreshed_Repos) & upper('All repositories have been refreshed.') =  upper(Check_Repos.T)) | Temp_Repo_Refresh_Retries => Repo_Refresh_Retries_Int
   address system 'zypper refresh' with output stem Check_Repos.
   T = Check_Repos.0
   Temp_Repo_Refresh_Retries += 1
   Temp_Count_Refreshed_Repos = 1
   Failed_Repo_List = 'Failed Repo List:'
  do I = 1 to Check_Repos.0
     if upper(word(Check_Repos.I, 1)) = upper('Repository') & pos(upper('is up to date.'), upper(Check_Repos.I)) > 0 then Temp_Count_Refreshed_Repos += 1
     else Failed_Repo_List = Failed_Repo_List = Check_Repos.I || ' '
  end /* do I */
  select
    when (Check_Repos.0 >= Temp_Count_Refreshed_Repos) then do
      Log_Data = 'A Repository failed to refresh, retrying ' || Repo_Refresh_Retries_Int - Temp_Repo_Refresh_Retries || ' more times'
      Log_Data = Failed_Repo_List
      call Log_to_File
    end /* when */
    when upper('All repositories have been refreshed.') <> upper(Check_Repos.T) then do
      Log_Data = 'Failed to get the message, All repositories have been refreshed.'
      call Log_to_File
    end /* when */
    otherwise nop
  end  /* select */
end /* do until  */
if Temp_Repo_Refresh_Retries => Repo_Refresh_Retries_Int & upper('All repositories have been refreshed.') <> upper(Check_Repos.T) then do
   Log_Data = '*** Fatal Error *** Ran out of Repository refresh retries aborting, you can try it from the command line by running: zypper refresh'
   call Log_to_File
   exit
end /* if do */

address system 'zypper list-updates >' || Work_Directory || '/' || 'Zypper_List_Updates.txt'
if length(stream(Work_Directory || '/' || 'Zypper_List_Updates.txt', 'C', 'QUERY EXISTS')) = 0 then do
   Log_Data = 'Patch file does not exists exiting: ' || Work_Directory || '/' || 'Zypper_List_Updates.txt'
   call Log_to_File
   exit
end /* if do */
address system 'grep -c ^v ' || Work_Directory || '/' || 'Zypper_List_Updates.txt' with output stem Patch_Count.
Log_Data = 'The number of patche(s) to download are: ' || Patch_Count.1
call Log_to_File
return

Get_Speed:procedure
parse arg Raw_Line
Module       = '                                                   Get_Speed'
/* trace(?I) */
Temp_Var = changestr('|', subword(Raw_Line, 2), ' ')
if words(Temp_Var) > 3 then do
   Temp_Hex        = word(Temp_Var, 1)
   Temp_OK         = word(Temp_Var, 2)
   Temp_Down_Speed = word(Temp_Var, 3)
   if datatype(left(Temp_Down_Speed, 1), 'N') = 0 then Temp_Down_Speed = '0B/s'
   if datatype(Temp_Hex, 'X') = 1 & Temp_OK = 'OK' then do
      Cnt_Temp = 0
      do until datatype(substr(Temp_Down_Speed, Cnt_Temp, 1), 'M') = 1 | Cnt_Temp > length(Temp_Down_Speed)
         Cnt_Temp += 1
      end /* do until */
      Temp_Speed_Mag = substr(Temp_Down_Speed, Cnt_Temp, 1)
      Temp_Speed_Num = substr(Temp_Down_Speed, 1, Cnt_Temp - 1)
      select
        when Temp_Speed_Mag = 'G' then Mult = 1024**3
        when Temp_Speed_Mag = 'M' then Mult = 1024**2
        when Temp_Speed_Mag = 'K' then Mult = 1024
        when Temp_Speed_Mag = 'B' then Mult = 1
        otherwise Mult = 0
      end /* select */
      Download_Speed = trunc(Temp_Speed_Num * Mult)
   end /* if do */
   else Download_Speed = 0
end /* if do */
return Download_Speed

/* Update average speed download count for Repo_Box */
Update_Repo_Box:
Module       = '                                             Update_Repo_Box'
/* trace(?I) */
Cnt_Write_Zkk_Repos_Every_Calls += 1
Cnt_Repo_Indx = 0
I = 1
/* Look through Repo_Box and find the correct repo index */
do until Repo_Box.1.I.1 = Repo_Used | Cnt_Repo_Indx > Repo_Box.1.0.0
   if datatype(Repo_Box.1.I.0, W) = 0 then return
   Cnt_Repo_Indx += 1
   I = Cnt_Repo_Indx
end /* do until */

/* Now that we know the correct repo find the correct URL in Repo_Box.2 */
Cnt_URL_Indx = 0
J = Cnt_URL_Indx
do until word(Repo_Box.2.I.J, 5) = Http_Used | Cnt_URL_Indx > Repo_Box.2.I.0
   if datatype(Repo_Box.2.I.0, W) = 0 then return
   Cnt_URL_Indx += 1
   J = Cnt_URL_Indx
end /* do until */
if Cnt_Repo_Indx <= Repo_Box.1.0.0 & Cnt_URL_Indx <= Repo_Box.2.I.0 then do
   Temp_Enabled = word(Repo_Box.2.I.J, 1)
   Temp_Avg_Down_Speed = word(Repo_Box.2.I.J, 2)
   Temp_Successes = word(Repo_Box.2.I.J, 3)
   Temp_Failures = word(Repo_Box.2.I.J, 4)
   Temp_Extras = subword(Repo_Box.2.I.J, 5)
   if datatype(Temp_Speed, N) = 0 then Temp_Speed = Temp_Avg_Down_Speed
  if Success_Flag = 1 then do
     Temp_Avg_Down_Speed = trunc((Temp_Avg_Down_Speed * Temp_Successes + Temp_Speed) / (Temp_Successes + 1))
     Temp_Successes += 1
     Repo_Box.2.I.J = Temp_Enabled || ' ' || right(Temp_Avg_Down_Speed, Speed_Pad_Size_Int, '0') || ' ' || right(Temp_Successes, 7, '0') || ' ' || right(Temp_Failures, 7, '0') || ' ' || Temp_Extras
  end /* if do */
  else do
    Temp_Failures += 1
    Temp_baseurl = word(Temp_Extras, 1)
    Temp_Extras  = Temp_baseurl || ' ' || date('I') || ' ' || time('N') || ' ' || subword(Temp_Extras, 2)
  end /* else do */
Repo_Box.2.I.J = subword(Temp_Enabled || ' ' || right(Temp_Avg_Down_Speed, Speed_Pad_Size_Int, '0') || ' ' || right(Temp_Successes, 7, '0') || ' ' || right(Temp_Failures, 7, '0') || ' ' || Temp_Extras, 1, 20)
Log_Data = substr(Queue_List.S, 2) || ' Updating Zkk Repo Line ' || Repo_Box.2.I.J
call Log_to_File
end /* if do */
if time('T') > (Last_Write_Repos + Write_Zkk_Repos_Every_Sec) | Cnt_Write_Zkk_Repos_Every_Calls > Write_Zkk_Repos_Every_Calls then call Write_Out_Zkk_Repos
return

Write_Out_Zkk_Repos:
Module       = '                                         Write_Out_Zkk_Repos'
Log_Data = 'Writing Zkk Repos to disk'
call Log_to_File

/* IPC to the forked Download_Loop wait for it to see it is time to write out Zkk_Repo_Files, we can not write the files and have ZK_downLoader trying to read them at the same time. */
if Exiting_Bool = 0 & Check_Thread_Still_Running(Parent_or_Child) = 1 then do
   rc = rxqueue('Set','Main_Tx_ZKK@127.0.0.1:5757')
   if queued() = 0 then queue 'TX'
   rc = rxqueue('Set', 'Main_Rx_ZKK@127.0.0.1:5757')
  do until Queued() > 0 | Check_Thread_Still_Running(Parent_or_Child) = 0
     rc = syssleep(0.1)
  end /* do until */
end /* if do */
/* trace(?I) */
 Last_Write_Repos = time('T')
 Cnt_Write_Zkk_Repos_Every_Calls = 0
do I = 1 to Repo_Box.1.0.0
   rc = stream('/etc/zkk_download_shim/repos.d/' || Repo_Box.1.I.1 || '.repo', 'C', 'OPEN WRITE REPLACE')
  do J = 1 to Repo_Box.2.I.0
     rc = lineout('/etc/zkk_download_shim/repos.d/' || Repo_Box.1.I.1 || '.repo', Repo_Box.2.I.J)
     Log_Data = 'Updating Zkk Repo line for file ' || Repo_Box.1.I.1 || ' ' || Repo_Box.2.I.J
     call Log_to_File
  end /* do J */
   rc = stream('/etc/zkk_download_shim/repos.d/' || Repo_Box.1.I.1 || '.repo', 'C', 'CLOSE')
   Log_Data = 'Updating Zkk Repo file /etc/zkk_download_shim/repos.d/' || Repo_Box.1.I.1 || '.repo'
   call Log_to_File
end /* do I */

rc = rxqueue('Set','Main_Tx_ZKK@127.0.0.1:5757')
if queued() > 0 then pull Junk_Var
return

Compact_Log_Matrix:
Module       = '                                          Compact_Log_Matrix'
/*   if datatype(Temp_Speed, W) = 0 then trace(?R) */
  Http_Used = ''
/*   trace(O) */
  Repo_Used = ''
/*   trace(R) */
  Temp_Speed = 0
  Temp_File_Name = ''
  Success_Flag = ''
  Message_Count = 0
  Num_in_Queue = Queued()
  do L = 1 to Num_in_Queue
     if queued() > 0 then parse pull Log_Data
     call Write_to_File
     Temp_Data = substr(Log_Data, 114)
     select
       when pos('ZKK_Repo_Stem.', Temp_Data) > 0 & pos('://', Temp_Data) > 0 then do
         Http_Used = word(Log_Data, words(Log_Data))
         Repo_Used = word(Log_Data, 5)
         Message_Count += 1
       end /* when */
       when pos('Aria2', Temp_Data) > 0 & pos('|OK', Temp_Data) > 0 & pos('B/s|', Temp_Data) > 0 & words(Log_Data) > 7 then do
         Temp_File_Name = substr(Temp_Data,lastpos('/', Temp_Data) + 1)
         Log_Data = '* Information * Processing Log for download Repo: ' || Repo_Used || ' HTTP: ' Http_Used || ' File_Name: ' || Temp_File_Name
         call Log_to_File
         Temp_Speed += Get_Speed(Temp_Data)
         Message_Count += 1
       end /* when */
       when pos('Aria2', Temp_Data) > 0 & pos('|ERR', Temp_Data) > 0 & pos('B/s|', Temp_Data) > 0 & words(Log_Data) > 7 then do
         Temp_Speed += Get_Speed(Temp_Data)
         Message_Count += 1
       end /* when */
       when pos('Aria2', Temp_Data) > 0 & pos('(OK):download completed.', Temp_Data) > 0 then do
         Success_Flag = 1
         Message_Count += 1
      end /* when */
      when pos('Aria2', Temp_Data) > 0 & pos('(ERR):error occurred.', Temp_Data) > 0 then do
        Success_Flag = 0
        Message_Count += 1
        if pos('://', Http_Used) > 0 & length(Repo_Used) > 0 & datatype(Temp_Speed, W) = 1 then call Update_Repo_Box
      end /* when */
      otherwise nop
     end /* select */
  end /* do L */
  if pos('://', Http_Used) > 0 & length(Repo_Used) > 0 & datatype(Temp_Speed, W) = 1 & datatype(Success_Flag, W) = 1 & Message_Count => 3 then call Update_Repo_Box
return

Log_Matrix:
do until Get_Process_Count('ZK_d[o]wnLoader') = 0 & Check_Thread_Still_Running(Parent_or_Child) = 0
   Module      = '                                                  Log_Matrix'
   /* trace(?I) */
   rc = rxqueue('Set',    'Thread_Log_ZKK@127.0.0.1:5757')
   Num_in_Queue = queued()
   do U = 1 to Num_in_Queue
      parse pull Log_Data
      call Write_to_File
   end /* do U */
   rc = Batch_Queue('ZK_d[o]wnLoader')
   do S = 1 to Queue_List.0
      if PID_In_Mem.S = 0 then do
         Q_Thread = Queue_List.S || '@127.0.0.1:5757'
         rc = rxqueue('Set', Q_Thread)
         Say 'Processing Log Queue for: ' || Queue_List.S
         Log_Data = 'Processing Log Queue for: ' || substr(Queue_List.S, 2) || ' # in queue ' || queued()
         call Log_to_File
         call Compact_Log_Matrix
         rc = rxqueue('Delete', Q_Thread)
      end /* if do */
   end /* do S */
end /* do until */
return

Check_PID_Still_Running:procedure
parse arg PID_Num
if PID_Num <> 0 & datatype(PID_Num, W) = 1 then address system 'ps -p ' || PID_Num || ' -o comm=' with output stem PID_Search.
else PID_Search.0 = 0
PID_Search.0 = sign(PID_Search.0)
return PID_Search.0

Check_Thread_Still_Running:procedure
  parse arg PID_Num
  drop PID_Search.
  if PID_Num <> 0 & datatype(PID_Num, W) = 1 then address system 'ps -ef | grep z[k]k | grep ' PID_Num with output stem PID_Search.
  else PID_Search.0 = 0
  if PID_Search.0 = 1 & pos('<defunct>', PID_Search.1) > 0 then PID_Search.0 = 0
  PID_Search.0 = sign(PID_Search.0)
/*   say 'PID_Search ' || PID_Search.0 || ' PID_Num ' || PID_Num || ' PID_Search ' || PID_Search.1 */
return PID_Search.0

/* Find the number of process running pass in the wanted module example c[p]u, removes the grep cpu call Process_Count('k[w]orker') */
Get_Process_Count:
procedure
parse arg Z_Module
/* trace(?I) */
address system 'ps -e --no-headers | grep -c ' || Z_Module with output stem Z_Grep.
/* say 'Z_Grep ' || Z_Grep.1 */
return Z_Grep.1

Get_Process_ID:
procedure
parse arg Z_Module
Module       = '                                              Get_Process_ID'
address system "ps -ef | grep " || Z_Module with output stem Z_Count.
if datatype(word(Z_Count.1,2),'W') = 1 then PID_INT = word(Z_Count.1,2)
else PID_INT = 'NA'
return PID_INT

Get_Free_Mem_MB:
procedure
address system "free -m" with output stem Free_Mem_Stem.
Free_Mem_MB = word(Free_Mem_Stem.2,words(Free_Mem_Stem.2))
if datatype(Free_Mem_MB,'W') = 1 then nop
else Free_Mem_MB = 'NA'
return Free_Mem_MB

Get_Free_Disk_MB:
procedure
parse arg D_Path
address system "df " || D_Path  with output stem Free_Disk_Stem.
Free_Disk_MB = word(Free_Disk_Stem.2, 4)
if datatype(Free_Disk_MB,'W') = 1 then nop
else Free_Disk_MB = 'NA'
return Free_Disk_MB

Pad_Left:procedure
parse arg Pad_String, Pad_Size, Pad_Char
/* Pad_String is the string to get padded, Pad_Size is output length of the string, Pad_Char to the char which is added to the left */
/* trace(?I) */
Pad_String = right(Pad_String, Pad_Size, Pad_Char)
return Pad_String

Remove_File:procedure expose Program_Name
  parse arg Full_File_Name
  /* Checking for * or a short path or spaces in path before calling rm */
Module       = '                                                 Remove_File'
if pos('*', Full_File_Name) = 0 | pos(' ', Full_File_Name) = 0 | length(Full_File_Name) > 8 then do
   address system 'rm ' Full_File_Name
   if length(stream(Full_File_Name, 'C', 'QUERY EXISTS')) = 0 then do
      Log_Data = 'Success, Removal of file : ' || Full_File_Name
      call Log_to_File
      Rtn_Value = 1
   end /* if do */
   else do
      Log_Data = '*** Failure ***  Removal of file failed exiting : ' || Full_File_Name
      call Log_to_File
      Rtn_Value = 0
      exit
   end /* else do */
end /* if do */
return Rtn_Value

/* I needed to speed up processing the writing of the log files, so instead of checking each one individually I batched it.  */
Batch_Queue:procedure expose Queue_List. PID_In_Mem.
parse arg Program_String
  drop Queue_List.
  drop PID_In_Mem.
  /* The following two lines do the processing in the Linux shell with grep, sed, cut and sort, putting every thing in a standard sorted form. */
  address system 'rxqueue /list | grep -E ^Z[1-9]\+[0-9]\* | sort -d' with output stem Queue_List.
/*   say 'Queue_List ' Queue_List.0 */
  if Queue_List.0 > 0 then address system 'ps -ef | grep ' || Program_String || ' | sed -e "s/\s\+/\ /g" | cut -d ' || d2c(39) || ' ' || d2c(39) || ' -f 2 | sed s/^/Z/g | sort -d' with output stem PID_List.
  P = 1
  PID_In_Mem.0 = Queue_List.0
  do Q = 1 to Queue_List.0
     if Queue_List.Q > PID_List.P then do
        do until Queue_List.Q <= PID_List.P | P => PID_List.0
           P += 1
        end /* do until */
     end /* if do */
     if Queue_List.Q = PID_List.P then PID_In_Mem.Q = 1
     else PID_In_Mem.Q = 0
  end /* do Q */
return 1

Check_Queue:procedure
  parse arg Queue_Name
  address system 'rxqueue /list' with output stem List_of_Queues.
  Queue_Exist = 0
  do Q = 1 to List_of_Queues.0
     if upper(List_of_Queues.Q) = upper(Queue_Name) then Queue_Exist = 1
  end /* do Q */
return Queue_Exist

/* This also pulls the log entries from the child processes, the downloaders this way I do not have to add the complexity of file locking which is a pain */

Log_to_File:
  Log_Data = Date('S') || ' ' || Time('L') || ' ' || Pad_Left(getpid(), 5, ' ') || ' ' || Pad_Left(Program_Name, 20, ' ') || ' ' || Pad_Left(Module, 60, ' ') || ' ' || Log_Data
  call Write_to_File
return

Write_to_File:
if To_File_Bool = 0 then do
   Current_Queue_Name = rxqueue('Get')
   rc = rxqueue('Set', 'Thread_Log_ZKK@127.0.0.1:5757')
   queue Log_Data
   rc = rxqueue('Set', Current_Queue_Name)
end /* if do */
else do
  rc = lineout(Log_File, Log_Data)
  if time('T') > Log_File_Timer then do
     rc = stream(Log_File, 'C', 'CLOSE')
     Log_File_Timer = time('T') + 20
  end /* if do */
end /* if do */
return
