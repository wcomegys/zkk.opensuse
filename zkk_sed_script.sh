#!/bin/bash
# Script to modify zkk and ZK_downLoader regina paths
Command_Start="#!"
Regina_Str=$(which regina)
echo ' '
Rtn_Int=${#Regina_Str}
if [ $Rtn_Int -eq 0 ]
   then echo "which regina returns null please check and follow the instructions to install Regina REXX 3.9.6 or higher, regina --version"
   else echo "Regina REXX is installed, checking version, regina --version"
fi
Regina_Ver_Str=$(regina --version)
Pretty_Ver_Str=${Regina_Ver_Str:8:17}
if [ $Pretty_Ver_Str = 'REXX-Regina_3.9.6' ]
   then echo "Regina version passes now editing regina path, line 1, in zkk and ZK_downLoader with sed"
elif [ $Pretty_Ver_Str = 'REXX-Regina_3.9.7' ]
   then echo "Regina version passes now editing regina path, line 1, in zkk and ZK_downLoader with sed"
else echo "Regina REXX version fails please upgrade your version of Regina REXX to 3.9.6 or higher."
fi
Full_Command="${Command_Start}${Regina_Str}"
sed "s|#!\/usr\/local\/bin\/regina|${Full_Command}|1" zkk.rex > zkk
echo "Adding +x to zkk"
chmod +x zkk
ls -l zkk

sed "s|#!\/usr\/local\/bin\/regina|${Full_Command}|1" ZK_downLoader.rex > ZK_downLoader
echo "Adding +x to ZK_downLoader"
chmod +x ZK_downLoader
ls -l ZK_downLoader
