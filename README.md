    • zkk gets the patch listing from zypper. 
    • Parallel patch downloading up to 42 at one time configurable, it also checks to see if the rpm signatures are good, provides SHA-256, SHA-1 and MD5 hash. I thought the SHA-512 is a little exuberant, and it is just more data to move. You can change the number of parallel downloads using aria2 while the program is running and it will adjust to to new setting up or down without restarting.  (My machines can not spawn the download program fast enough to get to that number, or maintain the logs fast enough, there is always a constraint.)
    • It builds a parallel zkk repo files in /etc/zkk_download_shim/repos.d these repo files support multiple download URLs which can be cycled through, up to 256. Average download speed is tracked so the fastest ones will be at the top on the list. YES, you can have multiple sources for the same patch file if the download fails the program will automatically pick a new one, no more pushing retry. Each entry (row) in the file contains a URL these can individually be enabled and disabled. 
    • In the zkk.conf file you can control how many times aria2 retries, how many times  ZK_downLoader will try other repos (URLs), how log it waits before retrying again, one download does not block another. 
    • Tracked by repo URL enabled, Average download speed, good downloads, failed downloads, failure date and time, these will roll off as new ones are added.
    • Logging in /var/log/zkk_download_shim, one log for all, with lines timestamped and with PID, program and repo. zkk does have a problem keeping up with writing the logs, this problem is non-blocking.
    • Before each dispatch cycle checks memory, diskspace free, and how many ZK_downLoader are running configurable in /etc/zkk_download_shim/zkk.conf
    Please see zkk.pdf
