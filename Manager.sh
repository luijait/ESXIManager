# colour definitions
title='\033[1;36m'
subtitle='\033[0;35m'
divider='\033[1,37m'
normal='\033[0;0m'
red='\033[0;31m'
green='\033[0;32m'
orange='\033[0;33m'
yellow='\033[1;33m'
print("Habla ahora o calla para siempre")
# add pause after function execution
wait(){
  printf "$yellow\nPress any key to continue$normal"
  while [ true ] ; do
  read -t 3 -n 1
  if [ $? = 0 ]; then
    return ;
  fi
  done
}
 
# get general vm stats from datastores
getstats(){
  clear
  vim-cmd vmsvc/getallvms | sort -n | sed 's/Annotation//'
  wait
}
 
# get current power status from all vms on hypervisor
# NB: formatting is not set correctly for VM names that are short (problem #1)
getpower(){
  clear
  vmid=$(vim-cmd vmsvc/getallvms | awk -F" " '{ print $1 }' | tail -n +2 | sort -n )
  printf $title"VM Power Status:\n\n"$yellow"hostname\tpower status\n"$normal
  for v in $(echo $vmid);
   do
    vmhostname=$(vim-cmd vmsvc/get.summary $v | awk -F\" '/name/ { print $2 }')
    vmstatus=$(vim-cmd vmsvc/power.getstate $v | tail -n +2 | awk '{ print $2 }')
    printf "$vmhostname,$vmstatus\n" | sed 's/,/\t/g'
  done
  wait
}
 
# check if vm is currently activated, if not ask to turn on
# NB: add an option to turn off VM gracefully.  not sure on the command here, research (problem #2)
pushpower(){
  clear
  vim-cmd vmsvc/getallvms
  printf $green"\nEnter VM ID: "$normal
  read vm
 
  checkstate=$(vim-cmd vmsvc/power.getstate $vm | tail -n +2)
  if [[ "$checkstate" == "Powered off" ]];
      then printf "VM $vm is currently $checkstate.\n\nAre you sure you want to power on this server? "
    elif [[ "$checkstate" == "Powered on" ]];
      then printf $orange"\nVM $vm is already powered on.  Nothing more to do here.\n"$normal && wait && return
  fi
 
  read choice
  if [[ $choice == "y" ]];
      then printf "Changing power state on VM$vm...$(vim-cmd vmsvc/power.on $vm)...Success."
    elif [[ $choice == "n" ]];
      then printf $red"Aborted."$normal
  fi
  wait
}
 
# set current time
# due to a limitation on ESXi software, the timezone cannot be shifted away from UTC
# NB: implement an NTP server lookup dependent on the server's location (problem #3)
pushtime(){
  clear
  year=$(date +%Y)
  month=$(date +%m)
  day=$(date +%d)
  hour=$(date +%H)
  min=$(date +%M)
  esxcli system time set -d $day -H $hour -m $month -M $min -y $year
  echo -e $green"time set to $day/$month/$year, $hour:$min\n"$normal
  wait
}
 
# send server stats to screen
# NB: add dynamic discovery of datastores and their corresponding sizes (problem #4)
#
# Things to include: cpu make and model
#                    current time
#                    correct datastore values
#
getinfo(){
  clear
  osver=$(uname -r)
  oscpucores=$(vsish -e ls /hardware/cpu/cpuList/ | wc -l)
  osram=$(vsish -e get /memory/comprehensive | awk -F":" '/Physical/ { print $2 }' | sed 's/\ KB//')
  osds1=$(df -h | awk '/datastore1/ { print $3" / "$2" Used"}')
  osds2=$(df -h | awk '/datastore2/ { print $3" / "$2" Used"}')
  ramcalc=$(echo "$(( ${osram%% *} / 1024 / 1024)) GB")
  dshst=$title"$(uname -n)\n\n"$normal
  dsver=$subtitle"os:   \t"$normal"VMware ESXi v$osver\n"
  dscpu=$subtitle"cpu:  \t"$normal$oscpucores" cores\n"
  dsram=$subtitle"ram:  \t"$normal"$ramcalc\n"
  dsds1=$subtitle"ds1:  \t"$normal"$osds1\n"
  dsds2=$subtitle"ds2:  \t"$normal"$osds2\n"
  printf "$dshst$dscpu$dsver$dsram$dsds1$dsds2"
  wait
}
 
# get today's logs
getlogs(){
  clear
  less /var/log/syslog.log | grep $(date +%Y\-%m\-%d) | more
  wait
}
 
# enter the esxi vsish shell
vshell(){
  clear
  printf $title"$(hostname) Shell\n\n"$subtitle
  vsish -e help && printf "\n$green" && vsish
  printf $red"\nSession killed.\n"$normal
  wait && getmenu
}
 
# set a vmdk to a higher value
# NB: various improvements to apply (problem #n)
expandvmdk(){
    clear
    printf $title"\nVMDK Disk Size Expander:\n\n$normal"
 
    # variable resets
    availspace=0
    chksize=0
    choice=0
    counter=0
    currsize=0
    currvmdksize=0
    dssize=0
    newsize=0
    newvmdksize=0
    powerstate=0
    proceed=0
    v=0
    vmdir=0
    vmdkchoice=0
    vmdkchosen=0
    vmid=0
    vmname=0
 
    [[ -f /tmp/results ]] && rm /tmp/results
 
    # get list of vms
    vmlist(){
      vim-cmd vmsvc/getallvms | awk -F\  '{ print $1" "$2 }' | sed 's/\ /\t/g'
      linebreak && read -p "Choose a VM ID: " vmid
    }
 
    # linebreak
    linebreak(){
      printf "\n"
    }
 
    # display vm disk sizes
    vmdksize(){
      vmname=$(vim-cmd vmsvc/getallvms | grep $vmid | awk '{ print $2 }')
      vmdir=/vmfs/volumes/$(vim-cmd vmsvc/getallvms | grep $vmid | awk -F\  '{ print $3 }' | sed 's/\[//;s/\]//')
 
      # display vmdk files (but not flat.vmdk)
      for v in $(find $vmdir/$vmname -name "$vmname*.vmdk" -not -name "*flat*.*");
        do
          counter=$(( counter + 1 ))
          dssize=$(grep "VMFS" $v | awk '{ print $2 }')
          chksize=$(echo $(($dssize * 512 / 1024 / 1024 / 1024)))
          linebreak && printf "$counter: $(echo $v | awk -F\/ ' { print $6 }') $chksize\n" >>/tmp/results
        done
      cat /tmp/results
      linebreak && read -p "Which VMDK to increase? " vmdkchoice
 
      if [[ $vmdkchoice == 1 ]];
        then vmdkchosen=$(cat /tmp/results | awk -F\  '/1:/ { print $2 }') && currsize=$(cat /tmp/results | awk -F\  '/1:/ { print $3 }')
      elif [[ $vmdkchoice == 2 ]];
        then vmdkchosen=$(cat /tmp/results | awk -F\  '/2:/ { print $2 }') && currsize=$(cat /tmp/results | awk -F\  '/2:/ { print $3 }')
      elif [[ $vmdkchoice == 3 ]];
        then vmdkchosen=$(cat /tmp/results | awk -F\  '/3:/ { print $2 }') && currsize=$(cat /tmp/results | awk -F\  '/3:/ { print $3 }')
      else printf $red"ABORTED.  Not a valid entry"$normal && wait && getmenu
      fi
    }
 
 
    # read user input for new disk size
    newsizeprompt(){
      printf "\n"
      read -p "What is the new size of the vmdk? " newsize
      if [[ $newsize -lt $currsize ]];
        then linebreak && printf $orange"WARNING:\ncannot expand vmdk file to a size lower than the current size.  aborting.\n"$normal && wait && getmenu
      elif [[ $newsize -eq $currsize ]];
        then linebreak && printf $orange"WARNING:\ncannot expand vmdk file to the same size.  aborting.\n"$normal && wait && getmenu
      elif [[ $newsize -gt $currsize ]];
        then linebreak && printf $green"ACCEPTED.  "$normal
      else linebreak && printf $orange"WARNING:\nSorry, an error has occurred.  Aborting.\n"$normal && wait && getmenu
      fi
    }
 
    checkstate(){
      powerstate=$(vim-cmd vmsvc/power.getstate $vmid | tail -n +2 | awk '{ print $2 }')
      if [[ $powerstate == "on" ]];
        then printf $orange"WARNING:\nThis server is currently active and changes cannot occur until it is offline.\nPlease power off VM or shutdown from client-side.\n"$normal && wait && getmenu
      elif [[ $powerstate == "off" ]];
        then printf $green"Server is safely offline, proceeding to make changes.\n"$normal
      else printf $orange"WARNING:\nUnknown value.  Aborting."$normal && wait && getmenu
      fi
    }
 
    applynewsize(){
      # datastore path used in df for availabel storage checking
      availspace=$(df -h $vmdir | tail -1 | awk -F\  '{ print $4 }' | sed 's/G//;s/T//')
 
      if [[ $newsize -gt $(echo $availspace | awk -F"." '{ print $1 }') ]] || [[ $newsize -eq $(echo $availspace | awk -F"." '{ print $1 }') ]];
        then linebreak && printf $red"CRITICAL:\nNot enough storage space remaining to apply this change.  Aborting.\n"$normal && wait && getmenu
      fi
 
      # calculate vmdk datastore sizes in bytes
      newvmdksize=$(echo "$(($newsize*1024*1024*1024/512))")
      currvmdksize=$(echo "$(($currsize*1024*1024*1024/512))")
      #linebreak && printf "Final Details:\n"
      linebreak && printf $yellow"REPLACING:$normal $(grep $currvmdksize $vmdir/$vmname/$vmdkchosen)"
      linebreak && printf $yellow"     WITH:$normal $(sed "s/${currvmdksize}/${newvmdksize}/" $vmdir/$vmname/$vmdkchosen | grep VMFS)\n"
      linebreak && read -p "Proceed? (y/n)" proceed
      if [[ $proceed == "y" ]];
        then $(sed -i "s/${currvmdksize}/${newvmdksize}/" $vmdir/$vmname/$vmdkchosen) && linebreak && printf "Changes made.\n" && return
      else linebreak && printf $orange"Aborted.\n"$normal && return
      fi
    }
 
    #function executions
    vmlist
    vmdksize
    newsizeprompt
    checkstate
    applynewsize
 
  wait
}
 
# display the main menu at start and after each executed function
getmenu(){
  clear
  choice=0
  printf $title$(hostname)" - VM Management:$normal\n\n \
-----------------------------------------------\n \
1. Get VM Details\n \
2. Get VM Power Status\n \
3. Change VM Power State\n \
4. Set the current time\n \
5. Get System Info\n \
6. Review todays log\n \
\n \
ADVANCED:
\n \
7. Expand VMDK\n \
8. VSISH Shell\n \
-----------------------------------------------\n\n \
0. Quit\n\n"
 
printf $yellow"Enter selection [0-8] >$normal"
read choice
 
if [[ $choice = 0 ]] || [[ $choice = "" ]]; then exit 0
  elif [[ $choice = 1 ]]; then getstats
  elif [[ $choice = 2 ]]; then getpower
  elif [[ $choice = 3 ]]; then pushpower
  elif [[ $choice = 4 ]]; then pushtime
  elif [[ $choice = 5 ]]; then getinfo
  elif [[ $choice = 6 ]]; then getlogs
  elif [[ $choice = 7 ]]; then expandvmdk
  elif [[ $choice = 8 ]]; then vshell
  else $getmenu
fi
}
 
# perform initial menu display
while true; do
  getmenu
done
