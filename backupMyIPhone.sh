#! /usr/bin/env nix-shell
#! nix-shell -i bash ./shell.nix

# Nvm: #!/bin/bash

set -e

continuous="$2" # (Optional) Set to 1 to make the backup wait for WiFi. If 1, $inc (aka $1) will be unused.
firstTime="$3" # (Optional) Set to 1 to re-setup device (only for `continuous` mode for now)
dryRun="$4" # (Optional) [Only works when $continuous == 1] Set to 1 to do a dry run (no changes to backup history + it will be verbose with `set -x`)

if [ "$dryRun" == "1" ]; then
    set -x
fi

if [ "$continuous" != "1" ] && [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi

chownExe()
{
    dest="$1"
    groupName="$(stat -c %G "$dest")"
    if [ "$?" != "0" ]; then
	exit
    fi
    if [ "$groupName" != "iosbackup" ]; then
	echo "chowning $dest for correct group"
	sudo chown :iosbackup "$dest"
    fi
    perms="$(stat -c %a "$dest")"
    if [ "$?" != "0" ]; then
	exit
    fi
    if [[ $perms != 75* ]]; then
	chmod 75${perms: -1} "$dest"
	if [ "$?" != "0" ]; then
	    exit
	fi
    fi
}

if [ "$continuous" == "1" ]; then
	mountpoint /mnt/ironwolf || { echo "Error: ironwolf drive not mounted. Exiting."; exit 1; }

	# The thing is, here, we need the device's ID to know how to reach it beforehand. So you need to provide a command-line argument for which device to connect to (UUID):
        deviceToConnectTo="$5" # Leave empty if $firstTime is 1

	# Prepare perms
	if [ "$EUID" -ne 0 ]; then
	    echo "Not root, not preparing perms"
	    if [ "$firstTime" == "1" ]; then
		echo "Need to be root for firstTime. Exiting."
		exit 1
	    fi
	else
	    echo "Root, preparing perms and then continuing"
	    dest='ibackup.sh'
	    chownExe "$dest"
	    dest='backupMyIPhone.sh'
	    chownExe "$dest"
	    dest='.'
	    chownExe "$dest"
	    dest='udidToFolderLookupTable.py'
	    chownExe "$dest"
	    #exit
	fi

	if [ ! -z "$deviceToConnectTo" ]; then
	    username="$(python3 ./udidToFolderLookupTable.py "$deviceToConnectTo")"
	    echo "Backing up as user $username"

	    if [ "$firstTime" == "1" ]; then
		sudo ./ibackup.sh "$deviceToConnectTo" "$firstTime" "$dryRun" "$port" "$username"
	    else
		# Run btrbk "daemon", as sudo so btrfs snapshots work
		echo "Starting btrbk daemon..."
		#port=$((8089 + $(id -u "$username")))
		port=8089
		sudo ./btrbk_daemon.py "" "" "$dryRun" "$port" &

		# Run it as a "daemon"
		sudo -E su --preserve-environment "$username" -- ./ibackup.sh "$deviceToConnectTo" "$firstTime" "$dryRun" "$port"
	    fi
	else
	    # First-time run
	    if [ "$firstTime" != "1" ]; then
		echo "Need to be firstTime to have no deviceToConnectTo. Exiting."
		exit 1
	    fi

	    # First-time setup with sudo
	    port=""
	    sudo ./ibackup.sh "$deviceToConnectTo" "$firstTime" "$dryRun" "$port"
	fi
	exit
fi

# Provide an existing directory in $1 to do an incremental backup:
inc="$1"

dt=$(date '+%Y-%m-%d %I-%M-%S %p')

# Need to warm up sudo
sudo echo 2>&1 | tee -a "$dt.log.txt"

sudo `which usbmuxd` -f 2>&1 | tee -a "$dt.log.txt" &

# Show some syslog output in the background as we go (so you can see why weird errors like this happen: { [...]
# [==================================================]  98% Finished
# [==================================================]  98% Finished
# [==================================================]  98% Finished
# [==================================================]  98% Finished
# [==================================================]  98% Finished
# [==================================================]  98% Finished
# [==================================================]  98% Finished
# [==================================================]  98% Finished
# [==================================================]  98% Finished
# [==================================================]  98% Finished
# [==================================================]  98% Finished
# [==================================================]  98% Finished
# [==================================================]  98% Finished
# [==================================================]  98% Finished
# [================================================= ]  98% Finished
# Receiving files
# [=                                                 ]   0% (65.6 KB/2.6 GB)     
# Received an error message from device: Input/output error (5)
# [==================================================]  98% Finished2.6 GB)       
# ErrorCode 104: Multiple errors uploading files (MBErrorDomain/104)
# Received 466277 files from device.
# Backup Failed (Error Code 104).
# sebastian@MacBookPro:/run/media/sebastian/5F906D2039164F88$ echo $?
# 152
# })
sudo idevicesyslog 2>&1 | tee -a "$inc$dt.log.txt" 1> /dev/null & # https://unix.stackexchange.com/questions/610329/is-it-safe-to-pipe-multiple-commands-output-to-the-same-file-simultaneously-usin : use tee's append option (`-a`)

directory="$dt"
mkdir "$directory"

# Only compatible with iOS 3 and below: idevicebackup backup "$directory" #--udid 00008020-000D29613C61002E

#idevicebackup2 info "$directory" # Show last backup
echo "---------1" 2>&1 | tee -a "$inc$dt.log.txt"
set +e
output=$(sudo `which idevicebackup2` encryption on SuperBewn "$directory" 2>&1 | tee -a "$inc$dt.log.txt") # Provide password and encrypt backups
res=$?
#echo "$res"
hasEnabledAlready=$(echo "$output" | grep -q 'Backup encryption is already enabled')
if [ -z "$hasEnabledAlready" ]; then
    # Allow nonzero exit codes to be ok
    echo "Backup encryption is already enabled" 2>&1 | tee -a "$inc$dt.log.txt"
    :
else
    # Error if exit code is nonzero
    if [ "$res" != "0" ]; then
	echo "$output" 2>&1 | tee -a "$inc$dt.syslog.txt"
	exit "$res"
    fi
fi
set -e
echo "---------2" 2>&1 | tee -a "$inc$dt.log.txt"
if [ -z "$inc" ]; then
    sudo `which idevicebackup2` --interactive backup --full "$directory" 2>&1 | tee -a "$inc$dt.log.txt" # Back up
else
    sudo `which idevicebackup2` --interactive backup "$inc" 2>&1 | tee -a "$inc$dt.log.txt" # Back up
fi

sudo pkill idevicesyslog
sleep 8
# Sometimes it doesn't kill gracefully, so kill it completely:
sudo pkill -9 idevicesyslog
sudo pkill usbmuxd
