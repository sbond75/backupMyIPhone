#! /usr/bin/env nix-shell
#! nix-shell -i bash ./shell.nix

# echo "$@"
# exit

# Based on https://valinet.ro/2021/01/20/Automatically-backup-the-iPhone-to-the-Raspberry-Pi.html
# This is a "daemon" for backing up iOS devices. It polls the device every day at 12:01 AM to try to back it up.
deviceToConnectTo="$1" # Leave empty for first-time setup
firstTime="$2"
dryRun="$3"
btrfsDaemonPort="$4"
username="$5" # Set this when running as root to do firstTime setup (only use when firstTime = 1)
ranWithTeeAlready="$6" # Internal use, leave empty
snapshotBeforeBackup="$7" # 1 to make a snapshot before backing up, then exit without backing up. Leave empty usually.
useUSB="$8" # 1 to backup via USB instead of WiFi. Requires root (will prompt for sudo access). This argument has no effect when running from systemd. Leave empty usually.
nixShellToUseForUSB="$9" # Only works when useUSB == 1. Leave blank to use ./shell_wifi_pair.nix as the nix shell for the libimobiledevice tools like ideviceinfo and idevicebackup2. If not blank, this should be the path to a nix shell file to use for USB backups.
quietUsbmuxd="$10" # Optional. 1 to make usbmuxd not print as much

if [ "$dryRun" == "1" ]; then
    set -x
fi

echo "[ibackup] Starting up with args $@"

if [ -z "$nixShellToUseForUSB" ]; then
    nixShellToUseForUSB='./shell_wifi_pair.nix'
elif [ "$useUSB" != 1 && ! -z "$ranWithTeeAlready" ]; then # (ranWithTeeAlready sets nixShellToUseForUSB so we can't check for it being non-empty here due to the above if-statement not being true)
    echo "Unsupported options provided: useUSB != 1 and nixShellToUseForUSB is not empty (it is $nixShellToUseForUSB). Exiting."
    exit 1
fi

makeSnapshot()
{
    local dest="$1"
    
	# Make snapshot
	if [ ! -e "$dest/@iosBackups" ]; then
		# # Make subvolume
		# echo "[ibackup] Creating Btrfs subvolume at $dest/@iosBackups"
		# cmd='btrfs subvolume create '"$dest/@iosBackups"
		# if [ "$dryRun" == "1" ]; then
		#     echo $cmd
		# else
		#     $cmd
		# fi

		echo "[ibackup] Fatal error: $dest/@iosBackups doesn't exist. It should have been created in firstTime setup earlier. Exiting."
		exit 1
	else
	    if [ -z "$(ls -A $dest/@iosBackups)" ]; then # https://superuser.com/questions/352289/bash-scripting-test-for-empty-directory
		echo "Empty $dest/@iosBackups folder, not snapshotting"
	    else
		# Make snapshot first (to save old backup status before an incremental backup which updates the old contents in-place). Only happens if onchange (if it changed -- https://manpages.debian.org/testing/btrbk/btrbk.conf.5.en.html ) #
		scriptDir="$(dirname "${BASH_SOURCE[0]}")"
		echo "[ibackup] btrbk Btrfs snapshot starting:"
		mountpoint "$config__drive" || { echo "Error: backup destination drive not mounted. Exiting."; exit 1; }
		if [ "$dryRun" == "1" ]; then
		    run=dryrun
		    #run=run
		else
		    run=run
		fi
		filename=$(basename -- "$ranWithTeeAlready")
		extension="${filename##*.}"
		filename="${filename%.*}" # Without the extension ( https://stackoverflow.com/questions/965053/extract-filename-and-extension-in-bash )
		logfileBtrbk="$(dirname "$ranWithTeeAlready")/${filename}_btrbk_ibackup.txt"
		config=$(cat << EOF
transaction_log            $logfileBtrbk
stream_buffer              512m
snapshot_dir               home/$username/_btrbk_snap
incremental                 yes
snapshot_preserve_min      7d
snapshot_preserve          14d
target_preserve_min        all
target_preserve            no
snapshot_preserve       14d
volume $config__drive
  snapshot_create  onchange
  subvolume home/$username/@iosBackups
EOF
)
		echo "$config"
		#btrbk --config=<(echo "$config") --verbose --preserve --preserve-backups --preserve-snapshots $run #run #dryrun             #"--preserve": "preserve all (do not delete anything)"                 # --loglevel=debug
		echo "$config" | python3 ./btrbk_run.py "$btrfsDaemonPort" # NOTE: doesn't use the nix shell shebang due to a minor issue with `sudo -E su --preserve-environment` followed by a username to run as, which is: `error: creating directory '/run/user/1000/nix-shell-600411-0': Permission denied`. Just using the python3 we have already fixes this issue.
		exitCode="$?"
		if [ "$exitCode" != "0" ]; then
		    echo "btrbk_run.py failed with exit code $exitCode"
		    exit
		fi
		#misc cool stuff: `sudo btrbk --config="$configLocation" diff` could be nice to find where a file was changed!
		echo "[ibackup] btrbk snapshot finished."
	    fi
	fi
}

scriptDir="$(dirname "${BASH_SOURCE[0]}")"
source "$scriptDir/teeWithTimestamps.sh" # Sets `tee_with_timestamps` function

# Grab config
source "$scriptDir/config.sh"

# https://stackoverflow.com/questions/18431285/check-if-a-user-is-in-a-group
is_in_group()
{
  groupname="$1"
  # The second argument is optional -- defaults to current user.
  current_user="$(id -un)"
  user="${2:-$current_user}"
  for group in $(id -Gn "$user") ; do
    if [ "$group" = "$groupname" ]; then
      return 0
    fi
  done
  # If it reaches this point, the user is not in the group.
  return 1
}

sudo()
{
    if [ "$useUSB" == "1" ]; then
	command sudo "$@" # https://stackoverflow.com/questions/6365795/invoking-program-when-a-bash-function-has-the-same-name
    elif [ "$EUID" -ne 0 ]; then
	echo "Not root, not running $@"
    else
	"$@"
    fi
}

# Begin basic interactive setup #
# Check group exists
g=iosbackup
u="$(id -un)"
if is_in_group "$g" "$u"; then
    :
elif [ "$EUID" -ne 0 ]; then
    if [ "$firstTime" == "1" ]; then
	echo "Must run as root for firstTime = 1. Exiting."
	exit 1
    fi
    
    echo "Your current user $u needs to be in group $g. (Tip: try \`sudo -E su --preserve-environment SomeUserInGroup_$g\` and then run this script.) Exiting."
    exit 1
else
    # "UDID -> folder name" lookup (config file essentially)
    # userFolderName=$(python3 ./udidToFolderLookupTable.py "$deviceToConnectTo")
    # echo "[ibackup] User folder name: $userFolderName"
    # u="$userFolderName"
    # if [ -z "$userFolderName" ]; then
    # 	echo "Empty name, exiting"
    # 	exit 1
    # fi
    :
fi

if [ -z "$username" ]; then
    username="$u"
fi
chownchmod()
{
    local dest="$1"
    
    # Get group ID and perms of dest
    #gid="$(stat -c %g "$dest")" # https://superuser.com/questions/581989/bash-find-directory-group-owner
    #groupName="$(getent group $gid | cut -d: -f1)" # https://stackoverflow.com/questions/29357095/linux-how-to-get-group-id-from-group-name-and-vice-versa
    groupName="$(stat -c %G "$dest")" # https://superuser.com/questions/581989/bash-find-directory-group-owner
    if [ "$?" != "0" ]; then
	exit
    fi
    # Chown dest folder if $groupName isn't what we expect
    if [ "$groupName" != "iosbackup" ]; then
	echo "chowning $dest for correct group"
	sudo chown :iosbackup "$dest"
    fi
    perms="$(stat -c %a "$dest")" # https://stackoverflow.com/questions/338037/how-to-check-permissions-of-a-specific-directory
    # Chmod dest folder if perms aren't what we expect, including the separate check (using Python) for whether the setgid bit is not set (based on https://stackoverflow.com/questions/2163800/check-if-a-file-is-setuid-root-in-python , https://docs.python.org/3/library/os.html#os.stat )
    if [ "$?" != "0" ]; then
	exit
    fi
    if [[ $perms != 77* || $(python3 -c << EOF
import os
from sys import argv
s=os.stat(argv[1])
if s.st_mode & stat.S_ISGID:
   print("1")
else:
   print("0")
EOF
    "$dest") == "0" ]]; then
	echo "chmoding $dest for correct perms"
	# Set the "setgid" bit using the `2` at the front here, which causes the group to be inherited for all files created within this directory ( https://linuxg.net/how-to-set-the-setuid-and-setgid-bit-for-files-in-linux-and-unix/ , https://unix.stackexchange.com/questions/115631/getting-new-files-to-inherit-group-permissions-on-linux : "It sounds like you're describing the setgid bit functionality where when a directory that has it set, will force any new files created within it to have their group set to the same group that's set on the parent directory." ) :
	chmod 277${perms: -1} "$dest" # https://stackoverflow.com/questions/17542892/how-to-get-the-last-character-of-a-string-in-a-shell
    fi
}
dest="$config__drive/home/$username"
scriptDir="$(dirname "${BASH_SOURCE[0]}")"
source "$scriptDir/destUsbmuxd.sh" # Sets `dest_usbmuxd` variable
makeDest()
{
    local dest="$1"
    local makeLogsFolder="$2"
    if [ ! -e "$dest" ]; then
	# Make destination folder
	echo "[ibackup] Creating $dest"
	sudo mkdir "$dest"
	if [ "$?" != "0" ]; then
	    exit
	fi
    fi
    if [ "$makeLogsFolder" = "1" ]; then
	if [ ! -e "$dest/logs" ]; then
	    # Create logs folder (for running with `| tee "$dest/logs/$(date '+%Y-%m-%d %I-%M-%S %p').log.txt"`)
	    echo "[ibackup] Creating $dest/logs"
	    sudo mkdir "$dest/logs"
	    if [ "$?" != "0" ]; then
		exit
	    fi

	    # Make it use compression
	    echo "[ibackup] Making $dest/logs use Btrfs compression"
	    btrfs property set "$dest/logs" compression zlib:9
	    if [ "$?" != "0" ]; then
		exit
	    fi
	    echo "[ibackup] Btrfs properties of $dest/logs is now:"
	    btrfs property get "$dest/logs"
	fi
    fi

    chownchmod "$dest"
    if [ "$makeLogsFolder" = "1" ]; then
	chownchmod "$dest/logs"
    fi
}
if [ "$EUID" -eq 0 ]; then
    if [ "$firstTime" != "1" ]; then
	echo "Must have firstTime = 1 when running as root. Exiting."
	exit 1
    fi
    echo "Running as root doing basic firstTime setup. Afterwards, run this script as a non-root user in the iosbackup group."
    
    mountpoint "$config__drive" || { echo "Error: backup destination drive not mounted. Exiting."; exit 1; }
    makeDest "$dest" 1
    makeDest "$dest_usbmuxd" 1
    if [ ! -e "$dest/@iosBackups" ]; then
	    # Make subvolume
	    echo "[ibackup] Creating Btrfs subvolume at $dest/@iosBackups"
	    cmd='sudo btrfs subvolume create '"$dest/@iosBackups"
	    if [ "$dryRun" == "1" ]; then
		echo $cmd
	    else
		$cmd
	    fi
    fi
    makeDest "$dest/@iosBackups" 0

    snaps="$dest/_btrbk_snap"
    mountpoint "$config__drive" || { echo "Error: backup destination drive not mounted. Exiting."; exit 1; }
    if [ ! -e "$snaps" ]; then
	parent="$(dirname "$snaps")"
	# "If you want an error when parent directories don't exist, and want to create the directory if it doesn't exist, then you can test [ https://pubs.opengroup.org/onlinepubs/009695399/utilities/test.html ] for the existence of the directory first:" ( https://stackoverflow.com/questions/793858/how-to-mkdir-only-if-a-directory-does-not-already-exist )
	[ -d "$parent" ] || sudo mkdir "$parent" # We use this instead of `mkdir -p` in case it isn't mounted for some possible case even though we checked `mountpoint` above I guess it could get unmounted in the time between the above `mountpoint` call and this line.
	if [ "$?" != "0" ]; then
	    exit
	fi
	sudo mkdir "$snaps"
	if [ "$?" != "0" ]; then
	    exit
	fi
	perms="$(stat -c %a "$snaps")"
	if [ "$?" != "0" ]; then
	    exit
	fi
	sudo chown :iosbackup "$snaps"
	if [ "$?" != "0" ]; then
	    exit
	fi
	chmod 277${perms: -1} "$snaps"
	if [ "$?" != "0" ]; then
	    exit
	fi
    fi
else
    #exit 0

    # Re-run with tee if needed
    if [ -z "$ranWithTeeAlready" ]; then
	logfile="$dest/logs/$(date '+%Y-%m-%d %I-%M-%S %p').log.txt"
	echo "[ibackup] Running with tee to logfile $logfile"
	bash "$0" "$deviceToConnectTo" "$firstTime" "$dryRun" "$btrfsDaemonPort" "$username" "$logfile" "$snapshotBeforeBackup" "$useUSB" "$nixShellToUseForUSB" "$quietUsbmuxd" 2>&1 | tee_with_timestamps "$logfile"
	exit
    fi
fi

# if [ "$EUID" -ne 0 ]; then
#     :
# else
#     echo "Running as root and finished setup. Now run this script as a non-root user in the iosbackup group."
#     exit 0
# fi
# End basic interactive setup #

if [ "$firstTime" == "1" ]; then    
	# If it's not already running as root, close the beast so we can start up with USB support (which requires root)
	pgrep -u root usbmuxd || { sudo `which usbmuxd` -X;
	} # `||` runs if previous command fails (non-zero exit code), while `&&` runs if zero exit code ( https://unix.stackexchange.com/questions/22726/how-to-conditionally-do-something-if-a-command-succeeded-or-failed )
	#pgrep -u root usbmuxd && { sudo `which usbmuxd` -X; sleep 3; sudo pkill -9 -u root usbmuxd; }

	# (Note: `nix-shell` requires non-pure (no --pure) shebang at the top..)
        nix-shell ./shell_wifi_pair.nix --run 'sudo usbmuxd -v & { sleep 2; idevicepair wifi on; }' # Use this when on USB (to pair for the first time)

	# Close the above one again (idevicepair is different for wifi on)
	pgrep -u root usbmuxd || { sudo `which usbmuxd` -X;
	}
	
	# Fire up the beast (usbmuxd also spawns its own stuff) which grabs network devices but is also using sudo so we can access USB for this firstTime setup.
        sudo `which usbmuxd` -v & # This can be either "regular" usbmuxd (which doesn't seem to support WiFi comms properly) or usbmuxd2, based on the shell.nix used in the shebang. (So we want usbmuxd2.)

	sleep 5
	
        # List network devices (for sanity check)
        echo "List of network devices:"
        # (`-n` for using network devices)
        idevice_id -n

        if [ -z "$deviceToConnectTo" ]; then
                echo "Need to provide a UDID from the list above to run the backup on. Exiting."
                exit 1
        fi

        # Get info
        ideviceinfo --udid "$deviceToConnectTo" -n

        # Enable encryption (`-n` for network device connection)
        idevicebackup2 --udid "$deviceToConnectTo" -n -i encryption on

        # Optional (if a password wasn't set)
	read -p "Enable or change backup password (needed to get Health data like steps, WiFi settings, call history, etc. ( https://support.apple.com/en-us/HT205220 )) (y/n)? " -r
	if [[ ! $REPLY =~ ^[Yy]$ ]]
	then
	    idevicebackup2 -i changepw
	else
	    :
	fi

	# Close the beast so we can start up next time without USB support (which doesn't require root probably)
	sudo `which usbmuxd` -X

	echo "Re-run without firstTime to do the backup."
	exit
fi

if [ -z "$deviceToConnectTo" ]; then
        echo "Need to provide a UDID to run the backup on. Exiting."
        exit 1
fi

#echo "[ibackup] Starting network daemon..."
#usbmuxd -v --nousb &

# Run btrbk "daemon", as sudo so btrfs snapshots work
#echo "[ibackup] Starting btrbk daemon..."
# We use `which` for `sudo` below so we don't run the `sudo()` alias defined further up in this file:
#`which sudo` ./btrbk_daemon.py "$username" "$0" "$dryRun" &

if [ "$snapshotBeforeBackup" = "1" ]; then
    echo '[ibackup] Just making snapshot, then exiting'
    # Make a snapshot
    makeSnapshot "$dest"

    echo '[ibackup] Snapshot made. Exiting.'
    exit
fi

while true; do
try=0
    


#successOrFailLogsBaseFolder="/var/run/usbmuxd.d"
successOrFailLogsBaseFolder="$config__drive/home/iosbackup_usbmuxd/logs"
CURDATE="$successOrFailLogsBaseFolder/$(date +"%Y%m%d")_$username"
if [[ -f "$CURDATE" ]]; then
    contents="$(tail -n 1 "$CURDATE")"
else
    contents=
fi
if [[ "$contents" == *"failed_with_too_many_attempts" ]] || [[ "$contents" == *"success" ]]; then
        echo "[ibackup] Backup for today exists; its status was ${contents}. (This status was found at ${CURDATE}.)"
        current_epoch=$(date +%s)
        target_epoch=$(date -d "tomorrow 00:00:01" +%s)
        to_sleep=$(( $target_epoch - $current_epoch ))
        echo "[ibackup] Sleeping for $to_sleep seconds (current epoch: $current_epoch)..."
        sleep $to_sleep
        #rm "$CURDATE"
fi
CURDATE="$successOrFailLogsBaseFolder/$(date +"%Y%m%d")_$username"

# backup
#echo "[ibackup] Killing network daemon..."
#usbmuxd -X
#echo "[ibackup] Starting network daemon..."
#usbmuxd -v --nousb

userOfRunningUsbmuxd="temp"
wantedUserOfRunningUsbmuxd="iosbackup_usbmuxd"
if [ "$useUSB" == "1" ]; then
    wantedUserOfRunningUsbmuxd="root"
fi
noStart=0
while [ ! -z "$userOfRunningUsbmuxd" ]; do
	userOfRunningUsbmuxd=$(ps -o user= -p $(pgrep usbmuxd) 2>/dev/null) # https://stackoverflow.com/questions/44758736/redirect-stderr-to-dev-null
	if [ ! -z "$userOfRunningUsbmuxd" ]; then
	    if [ "$wantedUserOfRunningUsbmuxd" == "$userOfRunningUsbmuxd" ]; then #if [ "$username" == "$userOfRunningUsbmuxd" ]; then
		noStart=1
		break
	    fi
	
	    seconds=60
	    echo "[ibackup] Waiting for usbmuxd of another user ($userOfRunningUsbmuxd) to finish (sleeping for $seconds seconds)..."
	    sleep "$seconds"
	fi
done
if [ "$useUSB" != "1" ]; then
    scriptDir="$(dirname "${BASH_SOURCE[0]}")"
    source "$scriptDir/spawnUsbmuxd.sh" # Spawn usbmuxd if noStart == 0
fi

echo "[ibackup] Waiting for network daemon..."
sleep 3
echo "[ibackup] Starting backup..."
#try=0
output=""
while : ; do
        ((try=try+1))
        #if [ $try -eq 1080 ]; then
	if [ $try -ge 100 ]; then
                #CURDATE="$successOrFailLogsBaseFolder/$(date +"%Y%m%d")_$username"
	        if [ "$dryRun" != "1" ]; then
                    echo failed_with_too_many_attempts | tee_with_timestamps "$CURDATE"
		fi
                break
        fi
	if [ "$useUSB" == "1" ]; then
	    extras=
	    extras2="bash $(printf '%q' "$scriptDir/runWithNixBash.sh") $(printf '%q' "$nixShellToUseForUSB")"
	else
	    extras="-n"
	    extras2=
	fi
	output=$($extras2 ideviceinfo --udid "$deviceToConnectTo" $extras 2>&1)
        dv=$?
        if [ $dv -eq 0 ]; then
                echo "[ibackup] Device is online."
		echo "[ibackup] (ideviceinfo output was:)"
		echo "$output"
		echo "[ibackup] (End of ideviceinfo output)"
                break
        fi
        echo "[ibackup] Device is offline (ideviceinfo output was $output), sleeping a bit until retrying [$try]..."
        sleep $((10 * try)) # "Linear" backoff (instead of exponential backoff or something like that, to retry again but wait longer each time)
done
if [[ -f "$CURDATE" ]]; then
    contents="$(tail -n 1 "$CURDATE")"
else
    contents=
fi
if [[ "$contents" == *"success" || "$contents" == *"failed" ]]; then
    echo "[ibackup] Weird thing that shouldn't really happen (but likely due to the ibackup script restarting): $CURDATE file says $contents at the end despite not having run the backup yet. (Backup will continue tomorrow, etc., as if it timed out waiting for the device too many times.) Contents of the entire file are: $(cat "$CURDATE")"
elif [[ "$contents" == *"failed_with_too_many_attempts" ]]; then
        echo "[ibackup] Timed out waiting for device, maybe we'll backup tomorrow."
else
        echo "[ibackup] Backing up..."
        #try=0

	# "UDID -> folder name" lookup (config file essentially)
	userFolderName=$(python3 ./udidToFolderLookupTable.py "$deviceToConnectTo")
	echo "[ibackup] User folder name: $userFolderName"
	if [ -z "$userFolderName" ]; then
	    echo "Empty name, exiting"
	    exit 1
	fi

	# if [ "$snapshotBeforeBackup" = "1" ]; then
	#     echo '[ibackup] Just making snapshot, then exiting'
	#     # Make a snapshot
	#     makeSnapshot "$dest"

	#     echo '[ibackup] Snapshot made. Exiting.'
	#     exit
	# fi
	
	# Back up
	if [ "$useUSB" == "1" ]; then
	    extras=
	    extras2="bash $(printf '%q' "$scriptDir/runWithNixBash.sh") $(printf '%q' "$nixShellToUseForUSB")"
	else
	    extras="-n"
	    extras2=
	fi
        cmd="$extras2 "'idevicebackup2 --udid '"$deviceToConnectTo"' '"$extras"' backup '"$config__drive/home/$username/@iosBackups"''
	if [ "$dryRun" == "1" ]; then
	    echo $cmd
	else
	    echo about_to_start_backup | tee_with_timestamps "$CURDATE"
	    $cmd
	fi
        dv=$?
	echo "[ibackup] Backup exit code: $dv"
        if [ $dv -eq 0 ]; then
                echo "[ibackup] Backup completed."
	    
                # Make a snapshot
		makeSnapshot "$dest"

		# Save backup status
                #CURDATE="$successOrFailLogsBaseFolder/$(date +"%Y%m%d")_$username"
	        if [ "$dryRun" != "1" ]; then
                    echo success | tee_with_timestamps "$CURDATE"
		fi
                echo "[ibackup] Saving backup status for today."
		try=0 # reset tries
        else
            #CURDATE="$successOrFailLogsBaseFolder/$(date +"%Y%m%d")_$username"
	    if [ "$dryRun" != "1" ]; then
                echo failed | tee_with_timestamps "$CURDATE"
	    fi
	    
            ((try=try+1))
            echo "[ibackup] Backup failed, sleeping a bit until retrying [$try]..."
            sleep $((10 * try))
        fi
fi
#echo "[ibackup] Killing network daemon..."
#usbmuxd -X


done
