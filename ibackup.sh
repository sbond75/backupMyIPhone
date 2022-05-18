#!/bin/bash

# Based on https://valinet.ro/2021/01/20/Automatically-backup-the-iPhone-to-the-Raspberry-Pi.html
# This is a "daemon" for backing up iOS devices. It polls the device every day at 12:01 AM to try to back it up.
deviceToConnectTo="$1" # Leave empty for first-time setup
firstTime="$2"

if [ "$firstTime" == "1" ]; then
	# If it's not already running as root, close the beast so we can start up with USB support (which requires root)
	pgrep -u root usbmuxd || { sudo `which usbmuxd` -X; sleep 3; sudo pkill -9 usbmuxd; #sudo rm /var/run/usbmuxd.pid; # Remove lockfile
	# Chown lockfile
	sudo chown :iosbackup /var/run/usbmuxd.pid
	sudo chmod g+w /var/run/usbmuxd.pid
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
                echo "Need to provide a UUID from the list above to run the backup on. Exiting."
                exit 1
        fi

        # Get info
        ideviceinfo --udid "$deviceToConnectTo" -n

        # Enable encryption (`-n` for network device connection)
        idevicebackup2 --udid "$deviceToConnectTo" -n -i encryption on

        # Optional (if a password wasn't set)
        #idevicebackup2 -i changepw

	# Close the beast so we can start up next time without USB support (which doesn't require root)
	sudo `which usbmuxd` -X
	sleep 3
	# Note: `%%` is the most recent job in Bash (jobs are started with `&`)
	kill -9 %% # Otherwise it doesn't close..
fi

if [ -z "$deviceToConnectTo" ]; then
        echo "Need to provide a UUID to run the backup on. Exiting."
        exit 1
fi

#echo "[ibackup] Starting network daemon..."
#usbmuxd -v --nousb &

while true; do



CURDATE=$(date +"%Y%m%d")
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
while [ ! -z "$userOfRunningUsbmuxd" ]; do
	userOfRunningUsbmuxd=$(ps -o user= -p $(pgrep usbmuxd) 2>/dev/null) # https://stackoverflow.com/questions/44758736/redirect-stderr-to-dev-null
	if [ ! -z "$userOfRunningUsbmuxd" ]; then
		seconds=60
		echo "[ibackup] Waiting for usbmuxd of another user ($userOfRunningUsbmuxd) to finish (sleeping for $seconds seconds)..."
		sleep "$seconds"
	fi
done
echo "[ibackup] Starting network daemon..."
usbmuxd -v --nousb &

echo "[ibackup] Waiting for network daemon..."
sleep 3
echo "[ibackup] Starting backup..."
try=0
output=""
while : ; do
        ((try=try+1))
        if [ $try -eq 1080 ]; then
                CURDATE=$(date +"%Y%m%d")
                echo failed > $CURDATE
                break
        fi
	output=$(ideviceinfo --uuid "$deviceToConnectTo" -n 2>&1)
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

	# "UUID -> folder name" lookup (config file essentially)
	userFolderName=$(./uuidToFolderLookupTable.py "$deviceToConnectTo")
	echo "[ibackup] User: $userFolderName"

	dest="/mnt/ironwolf/home/$username"
	if [ ! -e "$dest" ]; then
		# Make destination folder
		echo "[ibackup] Creating $dest"
		mkdir "$dest"
		# Make subvolume
		echo "[ibackup] Creating Btrfs subvolume at $dest/@iosBackups"
		btrfs subvolume create "$dest/@iosBackups"
	else
		# Make snapshot first (to save old backup status before an incremental backup which updates the old contents in-place). Only happens if onchange (if it changed -- https://manpages.debian.org/testing/btrbk/btrbk.conf.5.en.html ) #
		scriptDir="${BASH_SOURCE[0]}"
		echo "[ibackup] btrbk Btrfs snapshot starting:"
		mountpoint /mnt/ironwolf || { echo "Error: ironwolf drive not mounted. Exiting."; exit 1; }
		if [ ! -e /mnt/ironwolf/_btrbk_snap ]; then
			mkdir /mnt/ironwolf/_btrbk_snap
		fi
		btrbk --config=<(echo << EOF
transaction_log            btrbk_ibackup_$username.log
stream_buffer              512m
snapshot_dir               _btrbk_snap
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
) --verbose --preserve --preserve-backups --preserve-snapshots run #run #dryrun             #"--preserve": "preserve all (do not delete anything)"                 # --loglevel=debug
		#misc cool stuff: `sudo btrbk --config="$configLocation" diff` could be nice to find where a file was changed!
		echo "[ibackup] btrbk snapshot finished."
	fi

	# Back up
        idevicebackup2 --uuid "$deviceToConnectTo" -n backup "/mnt/ironwolf/home/$username/@iosBackups"
        dv=$?
        if [ $dv -eq 0 ]; then
                # save backup status
                echo "[ibackup] Backup completed."
                CURDATE=$(date +"%Y%m%d")
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
