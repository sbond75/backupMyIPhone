#! /usr/bin/env nix-shell
#! nix-shell --pure -i bash ./shell.nix

# echo "$@"
# exit

# Based on https://valinet.ro/2021/01/20/Automatically-backup-the-iPhone-to-the-Raspberry-Pi.html
# This is a "daemon" for backing up iOS devices. It polls the device every day at 12:01 AM to try to back it up.
deviceToConnectTo="$1" # Leave empty for first-time setup
firstTime="$2"
dryRun="$3"
btrfsDaemonPort="$4"
ranWithTeeAlready="$5" # Internal use, leave empty

if [ "$dryRun" == "1" ]; then
    set -x
fi

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
    if [ "$EUID" -ne 0 ]; then
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
    echo "Your current user $u needs to be in group $g. (Tip: try \`sudo -E su --preserve-environment SomeUserInGroup_$g\` and then run this script.) Exiting."
    exit 1
else
    # "UDID -> folder name" lookup (config file essentially)
    userFolderName=$(python3 ./udidToFolderLookupTable.py "$deviceToConnectTo")
    echo "[ibackup] User folder name: $userFolderName"
    u="$userFolderName"
    if [ -z "$userFolderName" ]; then
	echo "Empty name, exiting"
	exit 1
    fi
fi

username="$u"
dest="/mnt/ironwolf/home/$username"
mountpoint /mnt/ironwolf || { echo "Error: ironwolf drive not mounted. Exiting."; exit 1; }
if [ ! -e "$dest" ]; then
    # Make destination folder
    echo "[ibackup] Creating $dest"
    sudo mkdir "$dest"
    if [ "$?" != "0" ]; then
	exit
    fi
fi
if [ ! -e "$dest" ]; then
    # Create logs folder (for running with `| tee "$dest/logs/$(date '+%Y-%m-%d %I-%M-%S %p').log.txt"`)
    echo "[ibackup] Creating $dest/logs"
    sudo mkdir "$dest/logs"
    if [ "$?" != "0" ]; then
	exit
    fi
fi
# Re-run with tee if needed
if [ -z "$ranWithTeeAlready" ]; then
    logfile="$dest/logs/$(date '+%Y-%m-%d %I-%M-%S %p').log.txt"
    echo "[ibackup] Running with tee to logfile $logfile"
    bash "$0" "$deviceToConnectTo" "$firstTime" "$dryRun" "$btrfsDaemonPort" "$logfile" | tee "$logfile"
fi

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

snaps="$dest/_btrbk_snap"
mountpoint /mnt/ironwolf || { echo "Error: ironwolf drive not mounted. Exiting."; exit 1; }
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

if [ "$EUID" -ne 0 ]; then
    :
else
    echo "Running as root and finished setup. Now run this script as a non-root user in the iosbackup group."
    exit 0
fi
# End basic interactive setup #

if [ "$firstTime" == "1" ]; then    
	# If it's not already running as root, close the beast so we can start up with USB support (which requires root)
	pgrep -u root usbmuxd || { sudo `which usbmuxd` -X;
	} # `||` runs if previous command fails (non-zero exit code), while `&&` runs if zero exit code ( https://unix.stackexchange.com/questions/22726/how-to-conditionally-do-something-if-a-command-succeeded-or-failed )
	#pgrep -u root usbmuxd && { sudo `which usbmuxd` -X; sleep 3; sudo pkill -9 -u root usbmuxd; }

	# Fire up the beast (usbmuxd also spawns its own stuff) which grabs network devices but is also using sudo so we can acess USB for this firstTime setup.
        sudo `which usbmuxd` -v & # This can be either "regular" usbmuxd (which doesn't seem to support WiFi comms properly) or usbmuxd2, based on the shell.nix used in the shebang. (So we want usbmuxd2.)

        idevicepair wifi on # Use this when on USB (to pair for the first time)

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
        #idevicebackup2 -i changepw

	# Close the beast so we can start up next time without USB support (which doesn't require root probably)
	sudo `which usbmuxd` -X
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

while true; do



CURDATE=/var/run/usbmuxd.d/$(date +"%Y%m%d")
if [[ -f "$CURDATE" ]]; then
        echo "[ibackup] Backup for today exists."
        current_epoch=$(date +%s)
        target_epoch=$(date -d "tomorrow 00:00:01" +%s)
        to_sleep=$(( $target_epoch - $current_epoch ))
        echo "[ibackup] Sleeping for $to_sleep seconds (current epoch: $current_epoch)..."
        sleep $to_sleep
        rm $CURDATE
fi

# backup
#echo "[ibackup] Killing network daemon..."
#usbmuxd -X
#echo "[ibackup] Starting network daemon..."
#usbmuxd -v --nousb

userOfRunningUsbmuxd="temp"
noStart=0
while [ ! -z "$userOfRunningUsbmuxd" ]; do
	userOfRunningUsbmuxd=$(ps -o user= -p $(pgrep usbmuxd) 2>/dev/null) # https://stackoverflow.com/questions/44758736/redirect-stderr-to-dev-null
	if [ "$username" == "$userOfRunningUsbmuxd" ]; then
	    noStart=1
	    break
	fi
	if [ ! -z "$userOfRunningUsbmuxd" ]; then
		seconds=60
		echo "[ibackup] Waiting for usbmuxd of another user ($userOfRunningUsbmuxd) to finish (sleeping for $seconds seconds)..."
		sleep "$seconds"
	fi
done
if [ "$noStart" == "0" ]; then
    echo "[ibackup] Starting network daemon..."
    usbmuxd -vv --nousb --debug &
fi

echo "[ibackup] Waiting for network daemon..."
sleep 3
echo "[ibackup] Starting backup..."
try=0
output=""
while : ; do
        ((try=try+1))
        if [ $try -eq 1080 ]; then
                CURDATE=/var/run/usbmuxd.d/$(date +"%Y%m%d")
                echo failed > $CURDATE
                break
        fi
	output=$(ideviceinfo --udid "$deviceToConnectTo" -n 2>&1)
        dv=$?
        if [ $dv -eq 0 ]; then
                echo "[ibackup] Device is online."
		echo "[ibackup] (ideviceinfo output was:)"
		echo "$output"
		echo "[ibackup] (End of ideviceinfo output)"
                break
        fi
        echo "[ibackup] Device is offline, sleeping a bit until retrying [$try]..."
        sleep 10
done
if [[ -f "$CURDATE" ]]; then
        echo "[ibackup] Timed out waiting for device, maybe we'll backup tomorrow."
else
        echo "[ibackup] Backing up..."

	# "UDID -> folder name" lookup (config file essentially)
	userFolderName=$(python3 ./udidToFolderLookupTable.py "$deviceToConnectTo")
	echo "[ibackup] User folder name: $userFolderName"
	if [ -z "$userFolderName" ]; then
	    echo "Empty name, exiting"
	    exit 1
	fi

	if [ ! -e "$dest/@iosBackups" ]; then
		# Make subvolume
		echo "[ibackup] Creating Btrfs subvolume at $dest/@iosBackups"
		cmd='btrfs subvolume create "$dest/@iosBackups"'
		if [ "$dryRun" == "1" ]; then
		    echo $cmd
		else
		    $cmd
		fi
	else
		# Make snapshot first (to save old backup status before an incremental backup which updates the old contents in-place). Only happens if onchange (if it changed -- https://manpages.debian.org/testing/btrbk/btrbk.conf.5.en.html ) #
		scriptDir="${BASH_SOURCE[0]}"
		echo "[ibackup] btrbk Btrfs snapshot starting:"
		mountpoint /mnt/ironwolf || { echo "Error: ironwolf drive not mounted. Exiting."; exit 1; }
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
volume /mnt/ironwolf
  snapshot_create  onchange
  subvolume home/$username/@iosBackups
EOF
)
		echo "$config"
		#btrbk --config=<(echo "$config") --verbose --preserve --preserve-backups --preserve-snapshots $run #run #dryrun             #"--preserve": "preserve all (do not delete anything)"                 # --loglevel=debug
		echo "$config" | ./btrbk_run.py "$btrfsDaemonPort"
		exitCode="$?"
		if [ "$exitCode" != "0" ]; then
		    echo "btrbk_run.py failed with exit code $exitCode"
		    exit
		fi
		#misc cool stuff: `sudo btrbk --config="$configLocation" diff` could be nice to find where a file was changed!
		echo "[ibackup] btrbk snapshot finished."
	fi

	# Back up
        cmd='idevicebackup2 --udid '"$deviceToConnectTo"' -n backup '"/mnt/ironwolf/home/$username/@iosBackups"''
	if [ "$dryRun" == "1" ]; then
	    echo $cmd
	else
	    $cmd
	fi
        dv=$?
	echo "[ibackup] Backup exit code: $dv"
        if [ $dv -eq 0 ]; then
                # save backup status
                echo "[ibackup] Backup completed."
                CURDATE=/var/run/usbmuxd.d/$(date +"%Y%m%d")
                echo success > $CURDATE
                echo "[ibackup] Saving backup status for today."
        else
                echo "[ibackup] Backup failed, sleeping a bit until retrying..."
                sleep 10
        fi
fi
#echo "[ibackup] Killing network daemon..."
#usbmuxd -X


done
