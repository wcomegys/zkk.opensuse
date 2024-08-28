#!/usr/local/bin/regina
/* ZK_downLoader, part of zkk */
/* zkk, The Infinite Improbability Suse DownLoad Shim for zypper */
/* Apache License, Version 2.0 */

call rxfuncadd 'sysloadfuncs', 'regutil', 'sysloadfuncs'
call sysloadfuncs

/* trace(?I) */

parse arg Params
Call_Count     = word(Params, 1)
Repo_Name      = word(Params, 2)
Update_Archive = changestr('~', word(Params, 3), ' ')
File_Name      = word(Params, 4)

Prg_Downloader_Name = '       ZK_downLoader'
ZK_downLoader_version = '1.0.0'
ZK_downLoader_Debug = 0
numeric digits 16
Speed_Pad_Size_Int = 16

select
  when Call_Count = '--version' then do
    say Prg_Downloader_Name || ' version ' || ZK_downLoader_version
    exit
  end /* when do */
  when Call_Count = '-v'        then do
    say Prg_Downloader_Name || ' version ' || ZK_downLoader_version
    exit
  end /* when do */
  otherwise nop
end /* select */

/* Wait until the pid shows up in the Linux PID table */
do until Check_PID_Still_Running(getpid()) = 1
   rc = syssleep(0.1)
end /* do until */

/* Set up logging */
rc = rxqueue('S','SESSION@127.0.0.1:5757')
Q_Thread = 'Z' || getpid() || '@127.0.0.1:5757'
rc = rxqueue('Create', Q_Thread)
rc = rxqueue('Set', Q_Thread)

if length(stream('/etc/zkk_download_shim/zkk.conf', 'C', 'QUERY EXISTS')) > 0 then do
   Config_File = '/etc/zkk_download_shim/zkk.conf'
   if ZK_downLoader_Debug = 1 then do
      Log_Data = 'Normal Checking /etc/zkk_download_shim/zkk.conf file does exist'
      call Push_to_Queue
   end /* if do */
end /* if do */
else do
   Log_Data = '*** Fatal Error *** Configuration file /etc/zkk_download_shim/zkk.conf file does *NOT* exist, :exiting:'
   call Push_to_Queue
   exit
end /* else do */

ZKK_Repo_File_Name = '/etc/zkk_download_shim/repos.d/' || Repo_Name || '.repo'
if length(stream(ZKK_Repo_File_Name, 'C', 'QUERY EXISTS')) > 0 then do
   if ZK_downLoader_Debug = 1 then do
      Log_Data = 'Normal Checking ' || ZKK_Repo_File_Name || '.repo file does exist'
      call Push_to_Queue
   end /* if do */
end /* if do */
else do
   Log_Data = '*** Fatal Error *** Repo file ' || ZKK_Repo_File_Name || ' file does *NOT* exist, :exiting:'
   call Push_to_Queue
   exit
end /* else do */

if ZK_downLoader_Debug = 1 then do
   Log_Data = 'Processing Params expecting 4 parameters : ' || Params
   call Push_to_Queue
end /* if do */

if length(Repo_Name) = 0 then do
    Log_Data = '*** Error *** Repo_Name for repo not a valid string :exiting: ' || Repo_Name
    call Push_to_Queue
    exit
end /* if do */

if datatype(Call_Count, 'W') <> 1 then do
    Log_Data = '*** Error *** Call Count for repo not a valid Int :exiting: ' || Call_Count
    call Push_to_Queue
    exit
end /* if do */

if length(Update_Archive) = 0 then do
    Log_Data = '*** Error *** Update_Archive for repo not a valid string :exiting: ' || Update_Archive
    call Push_to_Queue
    exit
end /* if do */

if length(File_Name) = 0 then do
    Log_Data = '*** Error *** File_Name for repo not a valid Int :exiting: ' || File_Name
    call Push_to_Queue
    exit
end /* if do */

/* trace(?I) */
Saved_Directory = directory()

call Init

/* trace(?I) */
/* Build cache dir path */

Working_Cache_Directory = Cache_Directory || '/' || Repo_Name|| '/' || Update_Archive
if length(stream(Working_Cache_Directory, 'C', 'QUERY EXISTS')) = 0 then do
   address system 'mkdir -p ' || Working_Cache_Directory
   if length(stream(Working_Cache_Directory, 'C', 'QUERY EXISTS')) = 0 then do
      Log_Data = '*** Error *** Can not create Working_Cache_Directory : ' || Working_Cache_Directory
      call Push_to_Queue
      exit
   end /* if do */
   else do
      Log_Data = '* Information * Created Working_Cache_Directory : ' || Working_Cache_Directory
      call Push_to_Queue
   end /* else do */
end /* if do */

Full_Cache_File = Working_Cache_Directory || '/' || File_Name
if length(stream(Full_Cache_File, 'C', 'QUERY EXISTS')) <> 0 then do
    Log_Data = '* Information * File already EXISTS in cache directory, checking RPM to see if it is valid : ' || Full_Cache_File
    call Push_to_Queue
    RPM_Result_String = Check_Rpm(Full_Cache_File)
    if left(RPM_Result_String, 21)  = 'digests signatures OK' then do
       Log_Data = '* Information Exiting * File already EXISTS in cache directory, File: ' || Full_Cache_File || ', ' || RPM_Result_String
       call Push_to_Queue
       exit
    end /* if do */
    else do
      Log_Data = '** Warning ** File EXISTS in cache directory, rpm -checksig reports digests signatures are *NOT* valid, will remove file and download again : ' || Full_Cache_File
      call Push_to_Queue
      call Remove_File(Full_Cache_File)
      call Remove_Working_Dir_File(Full_Cache_File)
    end /* else do */
end /* if do */

call Read_Download_Repo

/* trace(?I) */

/* Remove file in Work Directory, this would be an aborted download */

rc = cd(Working_Cache_Directory)

Cnt_Total_Retries_Per_Loop_Int = 0
Aria2_Download_Good = 0
do until Cnt_Total_Retries_Per_Loop_Int > Max_Total_Retries_Per_Loop_Int | Aria2_Download_Good = 1
   /* Build URL index each time with does not go out of range because of modulo */
   if (ZKK_Repo_Stem.0 < Repo_Sites_Int | Repo_Sites_Int = 0 ) then U = ((Call_Count + Cnt_Total_Retries_Per_Loop_Int) // ZKK_Repo_Stem.0) + 1
   else U = ((Call_Count + Cnt_Total_Retries_Per_Loop_Int) // Repo_Sites_Int) + 1
   Log_Data = 'ZKK_Repo_Stem.' || U || ' is ' || ZKK_Repo_Stem.U
   call Push_to_Queue
   Working_URL = word(ZKK_Repo_Stem.U, 5) || '/' || Update_Archive || '/' || File_Name
   if pos('$releasever', Working_URL) > 0 then Working_URL = changestr('$releasever', Working_URL, Opensuse_Distro_Version)
   address system 'aria2c --connect-timeout=' || Connect_Timeout_Sec || ' --max-tries=' || Max_Retries_Per_Site_Int  ' --allow-overwrite=true --auto-file-renaming=false --lowest-speed-limit=' || Lowest_Speed_Limit_KB || ' --retry-wait=' || URL_Retry_Wait_Sec || ' --out=' || File_Name || ' '  || Working_URL with output stem Aria2c_Stem. error append stem Aria2c_Stem.
   do Z = 1 to Aria2c_Stem.0
      select
        when Aria2c_Stem.Z = '' then nop
        when pos('[1;32m', Aria2c_Stem.Z) > 0 & ZK_downLoader_Debug = 0 then nop
        when pos('[#', Aria2c_Stem.Z) > 0 & pos('%', Aria2c_Stem.Z) > 0 & ZK_downLoader_Debug = 0 then nop
        when pos('[#', Aria2c_Stem.Z) > 0 & pos('DL:0B]', Aria2c_Stem.Z) > 0 & ZK_downLoader_Debug = 0 then nop
        when pos('|stat|avg', Aria2c_Stem.Z) > 0 & ZK_downLoader_Debug = 0 then nop
        when pos('=====================================', Aria2c_Stem.Z) > 0 & ZK_downLoader_Debug = 0 then nop
        when pos('Status Legend:', Aria2c_Stem.Z) > 0 & ZK_downLoader_Debug = 0 then nop
        when pos('(OK):download completed.', Aria2c_Stem.Z) > 0 then do
          Log_Data = 'Aria2 ' || Aria2c_Stem.Z
          call Push_to_Queue
          RPM_Result_String = Check_Rpm(Full_Cache_File)
          if left(RPM_Result_String, 21)  = 'digests signatures OK' then do
             Log_Data = '* Information Exiting * File: ' || Full_Cache_File || ', ' || RPM_Result_String
             call Push_to_Queue
             Aria2_Download_Good = 1
          end /* if do */
          else do
            Log_Data = '* Information * File verification failed removing, will retry download : ' || Full_Cache_File
            call Push_to_Queue
            call Remove_File(Full_Cache_File)
            call Remove_Working_Dir_File(Full_Cache_File)
            Aria2_Download_Good = 0
          end /* else do */
        end /* when */
        when pos('cause: Network is unreachable', Aria2c_Stem.Z) > 0 then do
          Aria2_Download_Good = 0
          Log_Data = '** Warning ** Network is unreachable, could not download: ' Working_URL
          call Push_to_Queue
        end /* when */
        otherwise do
           Log_Data = 'Aria2 ' || Aria2c_Stem.Z
           call Push_to_Queue
        end /* otherwise do */
      end /* select */
   end /* do Z */
   Cnt_Total_Retries_Per_Loop_Int += 1
        if Aria2_Download_Good = 0 then sleep(URL_Retry_Wait_Sec)
end /* do until */
rc = cd(Saved_Directory)
exit

Init:
/* trace(?I) */

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
        call Push_to_Queue
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
        call Push_to_Queue
        Max_Concurrent_Downloads_Int = 8
     end /* else */
   end
   when upper('CONNECT_TIMEOUT_SEC')  = upper(word(In_Data, 1)) then do
     if (datatype(word(In_Data, 2), W) = 1 & word(In_Data, 2) => 5 & word(In_Data, 2) <= 300) then Connect_Timeout_Sec = word(In_Data, 2)
     else do
	    Log_Data = '** Warning ** Connect_Timeout_Sec 5 to 300, 0 how long aria2 waits to connect to the URL, default is 15 seconds : ' || word(In_Data, 2)
        call Push_to_Queue
        Connect_Timeout_Sec = 15
    end /* else */
   end
   when upper('URL_RETRY_WAIT_SEC')  = upper(word(In_Data, 1)) then do
     if (datatype(word(In_Data, 2), W) = 1 & word(In_Data, 2) => 1 & word(In_Data, 2) <= 300) then URL_Retry_Wait_Sec = word(In_Data, 2)
     else do
	    Log_Data = '** Warning ** URL_Retry_Wait_Sec 1 to 300, 0 how long aria2 waits to retry a download to the URL, default is 15 seconds : ' || word(In_Data, 2)
        call Push_to_Queue
        URL_Retry_Wait_Sec = 15
    end /* else */
   end
   when upper('LOWEST_SPEED_LIMIT_KB')  = upper(word(In_Data, 1)) then do
     if (datatype(word(In_Data, 2), W) = 1 & word(In_Data, 2) => 1 & word(In_Data, 2) <= 1024) then Lowest_Speed_Limit_KB = word(In_Data, 2) || K
     else do
	    Log_Data = '** Warning ** Lowest_Speed_Limit_KB 1 to 1024, This is the slowest speed aria2 will stay connected in Kilo Bytes per Second : ' || word(In_Data, 2) || 'K'
        call Push_to_Queue
        Lowest_Speed_Limit_KB = 1K
    end /* else */
   end
   when upper('MAX_RETRIES_PER_SITE_INT')  = upper(word(In_Data, 1)) then do
     if (datatype(word(In_Data, 2), W) = 1 & word(In_Data, 2) => 1 & word(In_Data, 2) <= 16) then Max_Retries_Per_Site_Int = word(In_Data, 2)
     else do
        Log_Data = '** Warning ** Max_Retries_Per_Site_Int is trying to be set out of bounds Int between 1 and 16 are valid: ' || word(In_Data, 2)
        call Push_to_Queue
        Max_Retries_Per_Site_Int = 2
     end /* else */
   end
   when upper('MAX_TOTAL_RETRIES_PER_LOOP_INT')  = upper(word(In_Data, 1)) then do
     if (datatype(word(In_Data, 2), W) = 1 & word(In_Data, 2) => 0 & word(In_Data, 2) <= 16) then Max_Total_Retries_Per_Loop_Int = word(In_Data, 2)
     else do
	    Log_Data = '** Warning ** Max_Total_Retries_Per_Loop_Int is trying to be set out of bounds Int between 0 and 16 are valid: ' || word(In_Data, 2)
        call Push_to_Queue
        Max_Total_Retries_Per_Loop_Int = 2
    end /* else */
   end
   when upper('REPO_SITES_INT')  = upper(word(In_Data, 1)) then do
     if (datatype(word(In_Data, 2), W) = 1 & word(In_Data, 2) => 0 & word(In_Data, 2) <= 256) then Repo_Sites_Int = word(In_Data, 2)
     else do
	    Log_Data = '** Warning ** Repo_Sites_Int 0 to 256, 0 is training mode and will loop through all repo sites : ' || word(In_Data, 2)
        call Push_to_Queue
        Repo_Sites_Int = 5
    end /* else */
   end
   when upper('WORK_DIRECTORY') = upper(word(In_Data, 1)) then do
     Temp_Data = word(In_Data, 2)
	 if (length(Temp_Data)) <= 2 then do
	    Log_Data = '*** Fatal Error *** Work_Directory path is less then or equal to 2 characters :exiting: ' || Temp_Data
        call Push_to_Queue
        exit
	 end /* if do */
	 if (left(Temp_Data,1) <> '/') then do
	    Log_Data = '*** Fatal Error *** Work_Directory path does not start with a / :exiting: ' || Temp_Data
        call Push_to_Queue
        exit
	 end /* if do */
	 do while (right(Temp_Data, 1) = '/')
        Temp_Data = substr(Temp_Data, 1, length(Temp_Data) - 1)
        if ZK_downLoader_Debug = 1 then do
	       Log_Data = 'House keeping Work_Directory path ends with a / removing: ' || Temp_Data
           call Push_to_Queue
        end /* if do */
	 end /* while */
	 if length(stream(Temp_Data, 'C', 'QUERY EXISTS')) = 0 then do
        Log_Data = '*** Fatal Error *** Work_Directory path does not exist, :exiting: ' || Temp_Data
        call Push_to_Queue
	    exit
	 end /* if do */
	  Work_Directory = Temp_Data
   end /* when */
   when upper('CACHE_DIRECTORY')  = upper(word(In_Data, 1)) then do
     Temp_Data = word(In_Data, 2)
	 if (length(Temp_Data)) <= 2 then do
	    Log_Data = '*** Fatal Error *** Cache_Directory path is less then or equal to 2 characters :exiting: ' || Temp_Data
        call Push_to_Queue
        exit
	 end /* if do */
	 if (left(Temp_Data,1) <> '/') then do
	    Log_Data = '*** Fatal Error *** Cache_Directory path does not start with a / :exiting: ' || Temp_Data
        call Push_to_Queue
        exit
	 end /* if do */
	 do while (right(Temp_Data, 1) = '/')
        Temp_Data = substr(Temp_Data, 1, length(Temp_Data) - 1)
        if ZK_downLoader_Debug = 1 then do
	       Log_Data = 'House keeping Cache_Directory path ends with a / removing: ' || Temp_Data
           call Push_to_Queue
        end /* if do */
	 end /* while */
	 if length(stream(Temp_Data, 'C', 'QUERY EXISTS')) = 0 then do
        Log_Data = '*** Fatal Error *** Cache_Directory path does not exist, :exiting: ' || Temp_Data
        call Push_to_Queue
	    exit
	 end /* if do */
	  Cache_Directory = Temp_Data
   end /* when */
   when upper('REPO_DIRECTORY')  = upper(word(In_Data, 1)) then do
     Temp_Data = word(In_Data, 2)
	 if (length(Temp_Data)) <= 2 then do
	    Log_Data = '*** Fatal Error *** Repo_Directory path is less then or equal to 2 characters :exiting: ' || Temp_Data
        call Push_to_Queue
        exit
	 end /* if do */
	 if (left(Temp_Data,1) <> '/') then do
	    Log_Data = '*** Fatal Error *** Repo_Directory path does not start with a / :exiting: ' || Temp_Data
        call Push_to_Queue
        exit
	 end /* if do */
	 do while (right(Temp_Data, 1) = '/')
        Temp_Data = substr(Temp_Data, 1, length(Temp_Data) - 1)
	    Log_Data = 'House keeping Repo_Directory path ends with a / removing: ' || Temp_Data
        call Push_to_Queue
	 end /* while */
	 if length(stream(Temp_Data, 'C', 'QUERY EXISTS')) = 0 then do
        Log_Data = '*** Fatal Error *** Repo_Directory path does not exist, :exiting: ' || Temp_Data
        call Push_to_Queue
	    exit
	 end /* if do */
	 rc = sysfiletree(Temp_Data || '/*.repo', Repo_Files.)
	 if (Repo_Files.0 = 0) then do
        Log_Data = '*** Fatal Error *** Repo_Directory does not contain any repo locations, :exiting: ' || Temp_Data
        call Push_to_Queue
	    exit
	 end /* if do */
	  Repo_Directory = Temp_Data
   end /* when */
   when upper('RUN_ZYPPER_AFTER_DOWNLOAD')  = upper(word(In_Data, 1)) then do
        if upper(word(In_Data, 2)) = 'Y' | upper(word(In_Data, 2)) = 'N' then Run_zypper_After_Download = word(In_Data, 2)
        else do
           Log_Data = '** Warning ** Run_zypper_After_Download Y or N are valid: ' || word(In_Data, 2)
           call Push_to_Queue
        end /* else */
   end
   when upper('RUN_ZYPPER_WITH_NO_CONFIRM')  = upper(word(In_Data, 1)) then do
        if upper(word(In_Data, 2)) = 'Y' | upper(word(In_Data, 2)) = 'N' then Run_zypper_with_No_Confirm = word(In_Data, 2)
        else do
	      Log_Data = '** Warning ** Run_zypper_with_No_Confirm Y or N are valid: ' || word(In_Data, 2)
          call Push_to_Queue
        end /* else */
   end
   when upper('RUN_ZYPPER_CLEAN_DEPS')  = upper(word(In_Data, 1)) then do
        if upper(word(In_Data, 2)) = 'Y' | upper(word(In_Data, 2)) = 'N' then Run_zypper_Clean_Deps = word(In_Data, 2)
        else do
	      Log_Data = '** Warning ** Run_zypper_Clean_Deps Y or N are valid: ' || word(In_Data, 2)
          call Push_to_Queue
        end /* else */
   end
   when upper('RUN_ZYPPER_OPTION')  = upper(word(In_Data, 1)) then do
        if lower(word(In_Data, 2)) = 'dup' | lower(word(In_Data, 2)) = 'up' then Run_zypper_Option = word(In_Data, 2)
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
        call Push_to_Queue
        Write_Zkk_Repos_Every_Sec = 300
    end /* else */
   end
   when upper('WRITE_ZKK_REPOS_EVERY_CALLS')  = upper(word(In_Data, 1)) then do
     if (datatype(word(In_Data, 2), W) = 1 & word(In_Data, 2) => 100 & word(In_Data, 2) <= 2000) then Write_Zkk_Repos_Every_Calls = word(In_Data, 2)
     else do
	    Log_Data = '** Warning ** Write_Zkk_Repos_Every_Calls is trying to be set out of bounds Int between 10 and 1000 are valid: ' || word(In_Data, 2)
        call Push_to_Queue
        Write_Zkk_Repos_Every_Calls = 2
    end /* else */
   end
   otherwise do
     Log_Data = "Don't know what this is: " || In_Data
     call Push_to_Queue
   end
 end /* select */
 end /* if do */
 else do
     Log_Data = 'Not at least 2 (two) words seperated by a space: ' || In_Data
     call Push_to_Queue
 end /* else do */
end /* do */
call Check_Opensuse_Version
return

Check_Opensuse_Version:
/* trace(?I) */
/* Read version file after Leap "version" Tumbleweed */
if length(stream('/etc/os-release', 'C', 'QUERY EXISTS')) = 0 then do
        Log_Data = '*** Fatal Error *** Can not open file /etc/os-release, :exiting: ' || Temp_Data
        call Push_to_Queue
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
      if ZK_downLoader_Debug = 1 then do
         Log_Data = 'Opensuse_Distro_Name is: ' || Opensuse_Distro_Name
         call Push_to_Queue
      end /* if do */
    end /* when */
    when Opensuse_Distro_Name = 'Leap' & datatype(Opensuse_Distro_Version, 'N') = 1 then do
      if ZK_downLoader_Debug = 1 then do
         Log_Data = 'Opensuse_Distro_Name is: ' || Opensuse_Distro_Name || ' and version number is: ' || Opensuse_Distro_Version
         call Push_to_Queue
      end /* if do */
    end /* when */
    otherwise do
      Log_Data = '*** Fatal Error *** Can not find NAME and VERSION in file /etc/os-release'
      call Push_to_Queue
      Log_Data = '*** Fatal Error *** Supported versions are SUSE Leap and Tumbleweed, :exiting:'
      call Push_to_Queue
      exit
    end /* otherwise */
  end /* select */
end /* else */
return

Read_Download_Repo:
 /*  trace(?I) */
  ZKK_Repo_Stem.0 = 0
  do until lines(ZKK_Repo_File_Name) = 0
     Temp_Var = linein(ZKK_Repo_File_Name)
     if ZK_downLoader_Debug = 1 then do
        Log_Data = 'Repo File Name: ' || ZKK_Repo_File_Name || ' Line being processed ' || Temp_Var
        call Push_to_Queue
     end /* if do */
     if words(Temp_Var) => 5 then do
        Temp_Enabled        = word(Temp_Var, 1)
        Temp_Avg_Down_Speed = word(Temp_Var, 2)
        Temp_Successes      = word(Temp_Var, 3)
        Temp_Failures       = word(Temp_Var, 4)
        Temp_baseurl        = word(Temp_Var, 5)
        if length(Temp_baseurl) = lastpos('/', Temp_baseurl) then Temp_baseurl = substr(Temp_baseurl, 1, length(Temp_baseurl) - 1)
       if words(Temp_Var)> 5 then Temp_Extras = subword(Temp_Var, 6) then do
         if datatype(Temp_Enabled, 'B') = 1 then do
            Temp_Enabled = abs(sign(Temp_Enabled))
            if ZK_downLoader_Debug = 1 then do
               Log_Data = 'Repo enabled 0 No 1 Yes: ' || Temp_Enabled
               call Push_to_Queue
            end /*if do */
         end /* if do */
         else do
         if ZK_downLoader_Debug = 1 then do
            Log_Data = 'Repo enabled is not 0 or 1 (one) or is set to 0 resetting to 0: ' || Temp_Enabled
            call Push_to_Queue
         end /* if do */
         Temp_Enabled = 0
         end /* else do */
         if datatype(Temp_Avg_Down_Speed, 'W') = 1 then do
            Temp_Avg_Down_Speed = Pad_Left(Temp_Avg_Down_Speed, Speed_Pad_Size_Int, '0')
            if ZK_downLoader_Debug = 1 then do
               Log_Data = 'Average Download Speed: ' || Temp_Avg_Down_Speed
               call Push_to_Queue
            end /* if do */
         end /* if do */
         else do
            if ZK_downLoader_Debug = 1 then do
               Log_Data = 'Average Download Speed not an integer resetting to 0: ' || Temp_Avg_Down_Speed
               call Push_to_Queue
            end /* if do */
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
                 if ZK_downLoader_Debug = 1 then do
                    Log_Data = 'Compatibility_Check: found tumbleweed in the baseurl string will not disable :' || Temp_baseurl
                    call Push_to_Queue
                 end /* if do */
               end /* if do */
               else do
                  Compatibility_Check = 0
                  Log_Data = '** Warning ** Compatibility_Check: Did *NOT* find tumbleweed in the baseurl string will disable :' || Temp_baseurl
                  call Push_to_Queue
               end /* else do */
             end /* when */
             when lower(Opensuse_Distro_Name) = 'leap' then do
               if (sign(pos('leap', lower(Temp_baseurl))) = 1 & ((sign(pos('$releasever', lower(Temp_baseurl))) = 1) | (sign(pos(Opensuse_Distro_Version, lower(Temp_baseurl))) = 1))) then do
                  Compatibility_Check = 1
                  if ZK_downLoader_Debug = 1 then do
                     Log_Data = 'Compatibility_Check: found leap and either $releasever or the leap version number in the baseurl string will not disable :' || Temp_baseurl
                     call Push_to_Queue
                  end /* if do */
               end /* if do */
               else do
                  Compatibility_Check = 0
                  Log_Data = '** Warning ** Compatibility_Check: Did *NOT* find leap and either $releasever or the leap version number in the baseurl string will disable :' || Temp_baseurl
                  call Push_to_Queue
               end /* else do */
            end /* when */
            otherwise Compatibility_Check = 0
         end /* select */
         if (length(Temp_baseurl) > 15) & (Protocol_Check = 1) & (Compatibility_Check = 1) then do
            if ZK_downLoader_Debug = 1 then do
               Log_Data = 'Found baseurl is longer than 15 and contains a valid protocol string :' || Temp_baseurl
               call Push_to_Queue
            end /* if do */
         end /* if do */
         else do
            Log_Data = 'baseurl is *NOT* longer than 15 or does *NOT* contain a valid protocol string, DISABLING repository line, enabled set to 0 :' ||  Temp_baseurl
            call Push_to_Queue
            Temp_Enabled = 0
         end /* else do */
         if datatype(Temp_Successes, 'W') = 1 then do
            if ZK_downLoader_Debug = 1 then do
               Log_Data = 'Download Successes is an Integer :' || Temp_Successes
               call Push_to_Queue
            end /* if do */
         end /* if do */
         else do
            Log_Data = 'Download Successes is *NOT* an integer resetting to 0 :' || Temp_Successes
            call Push_to_Queue
            Temp_Successes = 0
         end /* else do */
         if datatype(Temp_Failures, 'W') = 1 then do
            if ZK_downLoader_Debug = 1 then do
               Log_Data = 'Download Failures is an Integer: ' || Temp_Failures
               call Push_to_Queue
            end /* if do */
         end /* if do */
         else do
            Log_Data = 'Download Failures is *NOT* an integer resetting to 0: ' || Temp_Failures
            call Push_to_Queue
            Temp_Failures = 0
         end /* else do */
         if words(Temp_Var) => 5 & Temp_Enabled = 1 & Valid_Protocols.0 > 0 then do
            ZKK_Repo_Stem.0 += 1
            J = ZKK_Repo_Stem.0
            ZKK_Repo_Stem.J = Temp_Enabled || ' ' || Temp_Avg_Down_Speed || ' ' || Temp_Successes || ' ' || Temp_Failures || ' ' || Temp_baseurl
/*             Log_Data = 'ZKK_Repo_Stem.' || J || ' is ' || Temp_Enabled || ' ' || Temp_Avg_Down_Speed || ' ' || Temp_Successes || ' ' || Temp_Failures || ' ' || Temp_baseurl */
/*             call Push_to_Queue */
         end /* if do */
       end /* if do */
     else do
        Log_Data = 'Line not enabled or valid skipping ' ||  Temp_Var
        call Push_to_Queue
     end /* else do */
end /* do while */
  ZKK_Repo_Stem = sysstemsort(ZKK_Repo_Stem, 'DESCENDING')
return

Pad_Left:procedure
parse arg Pad_String, Pad_Size, Pad_Char
/* Pad_String is the string to get padded, Pad_Size is ouput length of the string, Pad_Char to the char which is added to the left */
if Pad_Size = '' then Pad_Size = 16
if datatype(Pad_Size, 'W') = 0 then Pad_Size = abs(16)
if datatype(Pad_Size, 'W') = 1 then Pad_Size = abs(Pad_Size)
if Pad_Char = '' then Pad_Char = ' '
if length(Pad_Char) > 1 then Pad_Char = left(Pad_Char, 1)
if length(Pad_String) > Pad_Size then Pad_String = left(Pad_String, Pad_Size)
do P = 1 to (Pad_Size - length(Pad_String))
  Pad_String = Pad_Char || Pad_String
end /* do S */
return Pad_String

/* Find the number of processes running pass in the wanted module example c[p]u, removes the grep cpu call Process_Count('k[w]orker') */
Check_Rpm:procedure expose Prg_Downloader_Name Repo_Name
  parse arg Full_Work_File
  if length(stream(Full_Work_File, 'C', 'QUERY EXISTS')) <> 0 then do
     address system "rpm -checksig " || Full_Work_File with output stem RPM_Stem. error append stem RPM_Stem.
    if (RPM_Stem.0 > 0) then do
      RPM_Result_String = subword(RPM_Stem.1, 2)
      address system 'sha256sum ' || Full_Work_File with output stem SHA_256_Stem. error append stem SHA_256_Stem.
      address system 'sha1sum ' || Full_Work_File with output stem SHA_1_Stem. error append stem SHA_1_Stem.
      address system 'md5sum ' || Full_Work_File with output stem MD5_Stem. error append stem MD5_Stem.
      RPM_Result_String = RPM_Result_String || ', SHA-256 Hash: ' || word(SHA_256_Stem.1, 1) || ', SHA-1 Hash: ' || word(SHA_1_Stem.1, 1) || ', MD5 Hash: ' || word(MD5_Stem.1, 1)
    end /* if do */
    else RPM_Result_String = 'Invalid result'
  end /* if do */
  else RPM_Result_String = 'File does not exist'
return RPM_Result_String

Check_PID_Still_Running:procedure
parse arg PID_Num
if PID_Num <> 0 & datatype(PID_Num, W) = 1 then address system 'ps -p ' || PID_Num || ' -o comm=' with output stem PID_Search.
else PID_Search.0 = 0
PID_Search.0 = sign(PID_Search.0)
return PID_Search.0

Remove_File:procedure expose Prg_Downloader_Name Repo_Name
  parse arg Full_File_Name
  /* Checking for * or a short path or spaces in path before calling rm */
if pos('*', Full_File_Name) = 0 | pos(' ', Full_File_Name) = 0 | length(Full_File_Name) > 8 then do
   address system 'rm ' Full_File_Name
   if length(stream(Full_File_Name, 'C', 'QUERY EXISTS')) = 0 then do
      Log_Data = 'Success, Removal of file : ' || Full_File_Name
      call Push_to_Queue
      Rtn_Value = 1
   end /* if do */
   else do
      Log_Data = '*** Failure ***  Removal of file failed :exiting: ' || Full_File_Name
      call Push_to_Queue
      Rtn_Value = 0
      exit
   end /* else do */
end /* if do */
return Rtn_Value

Remove_Working_Dir_File:procedure expose Prg_Downloader_Name Repo_Name
  parse arg Full_File_Name
  /* I wrote this for Aria2 it has an issue with files when it auto renames a download */
  /* Checking for * or a short path or spaces in path before calling rm */
/* trace(?I) */
Full_Length_File_Name = length(Full_File_Name)
Full_LPos_File_Name = lastpos('.rpm',Full_File_Name)
Full_LSlash_File_Name = lastpos('/',Full_File_Name)

 if pos('*', Full_File_Name) = 0 | pos(' ', Full_File_Name) = 0 | length(Full_File_Name) > 8 then do
    if length(stream(Full_File_Name, 'C', 'QUERY EXISTS')) <> 0 then do
       Log_Data = '* Information * File EXISTS in Work_Directory, will remove file : ' || Full_File_Name
       call Push_to_Queue
       address system 'rm ' Full_File_Name
       if length(stream(Full_File_Name, 'C', 'QUERY EXISTS')) = 0 then do
          Log_Data = 'Success, Removal of file : ' || Full_File_Name
          call Push_to_Queue
          Rtn_Value = 1
        end /* if do */
        else do
          Log_Data = '*** Failure ***  Removal of file failed : ' || Full_File_Name
          call Push_to_Queue
        end /* else do */
    end /* if do */
  if Full_LSlash_File_Name < Full_LPos_File_Name & (Full_Length_File_Name - Full_LPos_File_Name) < 4 then do
     Working_File_Del_Wildcard = insert('*.', Full_File_Name, Full_LPos_File_Name)
     rc = sysfiletree(Working_File_Del_Wildcard, Del_Temp_Files., of)
     do D = 1 to Del_Temp_Files.0
        address system 'rm ' Del_Temp_Files.D
        if length(stream(Del_Temp_Files.D, 'C', 'QUERY EXISTS')) = 0 then do
           Log_Data = 'Success, Removal of file : ' || Del_Temp_Files.D
           call Push_to_Queue
           Rtn_Value = 1
        end /* if do */
        else do
           Log_Data = '*** Failure ***  Removal of file failed : ' || Del_Temp_Files.D
           call Push_to_Queue
           Rtn_Value = 0
        end /* else do */
     end /* do D */
  end /* if do */
  else do
    Log_Data = '** Warning **  Removal of file failed an * <SPACE> or length was not greater than 8 char : ' || Full_File_Name
    call Push_to_Queue
  end /* else do */
 end /* if do */
return Rtn_Value

Push_to_Queue:
   queue Date('S') || ' ' || Time('L') || ' ' || Pad_Left(getpid(), 5, ' ') || ' ' || Pad_Left(Prg_Downloader_Name, 20, ' ') || ' ' || Pad_Left(Repo_Name, 60, ' ') || ' ' || Log_Data
return
