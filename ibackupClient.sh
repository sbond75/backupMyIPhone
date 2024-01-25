#!/usr/bin/env bash

##! /usr/bin/env nix-shell
##! nix-shell -i bash ./shell_new_libimobiledevice.nix

# NOTE: For setup, run these commands on the client (assumed to be a Raspberry Pi -- tested on `Raspbian GNU/Linux 9.13 (stretch)` (armv7l architecture) on a `Raspberry Pi 3 Model B Rev 1.2`):
# (Set up SSH as needed, wpa_supplicant, etc.)
# sudo apt update && sudo apt upgrade
# # Nvm: sh <(curl -L https://nixos.org/nix/install) --daemon  # Installs nix
# git clone --recursive https://github.com/sbond75/backupMyIPhone
# Nvm: {
# sudo apt-get install smbclient
# sudo apt-get install cifs-utils
# }
# sudo apt install lftp
# # Can use this instead of rclone but it is slow (in the kilobytes per second): sudo apt-get install curlftpfs
# # nvm, is too old version (v1.35, latest is v1.63.1 and we will use the command line mount without config settings, just command line arguments, and this old version doesn't have that.) sudo apt install rclone  # faster?
# # nvm, is too new version, fusermount3 command not found (fuse3 is needed for rclone deb above also (to have the fusermount3 command -- https://github.com/rclone/rclone/issues/6844 ) but there is no package that I can find so I can't use rclone really..): mkdir iphone_libs ; cd iphone_libs && wget https://downloads.rclone.org/v1.63.1/rclone-v1.63.1-linux-arm-v7.deb && sudo dpkg -i *.deb   # List of downloads is on https://rclone.org/downloads/
# mkdir iphone_libs ; cd iphone_libs && wget https://downloads.rclone.org/v1.52.3/rclone-v1.52.3-linux-arm.deb && sudo dpkg -i *.deb   # List of downloads is on https://rclone.org/downloads/

# sudo apt-get install netcat
# # Transfer the certificate from server into whatever you put in config.sh for `config__certPath`, then test out your connection using this command, replacing `usernameHere_ftp` with the FTP username (run `source config.sh` first):
# lftp -d -u usernameHere_ftp -e 'set ftp:ssl-force true' -e 'set ssl:ca-file '"$config__certPath ; set ssl:check-hostname false;" $config__host  # FTP test command
# # Compile libimobiledevice (Nix doesn't seem to work on armv7l as of writing) :
# bash compile_libimobiledevice_imperatively.sh

if [ "$(whoami)" != "pi" ]; then
    echo 'This script must be run as the `pi` user. Exiting.'
    exit 1
fi

set -e
#set -ex

# Sync network time for the raspberry pi (you may also need to set the timezone, such as by running `timedatectl set-timezone yourTimeZoneHere` (for a list of timezones, use `timedatectl list-timezones`)).
timedatectl

ranWithTeeAlready="$1" # Internal use, leave empty
firstTime="$2" # Set to 1 to pair and enable backup encryption interactively
useLocalDiskThenTransfer="$3" # Optional; set to `1` to use `config__localDiskPath` from `config.sh` to save backup to this path instead of to an FTP-mounted folder. Then, once the backup is finished, `lftp` is used to transfer the files to the server.
downloadFromServerFirst="$4" # Optional; set to `0` to not download the existing server files from the server first.
indicateOnLED="$5" # Optional; set to `1` to indicate backup status on the LED of this computer as a raspberry pi using `/sys/class/leds/led0/trigger`. If set to 1, this script will (at startup) check its permissions and adjust them to be owned by `pi` user if needed.

if [ -z "$downloadFromServerFirst" ]; then
    downloadFromServerFirst=1
fi

# Script setup #
scriptDir="$(dirname "${BASH_SOURCE[0]}")"
source "$scriptDir/teeWithTimestamps.sh" # Sets `tee_with_timestamps` function

# Grab config
source "$scriptDir/config.sh"
if [ ! -e "$config__clientDirectory" ]; then
    mkdir "$config__clientDirectory"
fi

dest="$config__clientDirectory"
if [ ! -e "$dest" ]; then
    mkdir "$dest"
fi

logfile="$dest/ibackupClient_logs/$(date '+%Y-%m-%d %I-%M-%S %p').log.txt"
logsDir="$(dirname "$logfile")"
if [ ! -e "$logsDir" ]; then
    mkdir "$logsDir"
fi

# Re-run with tee if needed
if [ -z "$ranWithTeeAlready" ]; then
    echo "[ibackupClient] Running with tee to logfile $logfile"
    bash "$0" "$logfile" "$firstTime" "$useLocalDiskThenTransfer" "$downloadFromServerFirst" "$indicateOnLED" 2>&1 | tee_with_timestamps "$logfile"
    exit
fi
# #






# Grab functions (and config which was actually already grabbed)
source ibackupClient_common.sh

# Prepare LED permissions if needed
oldTrap=
if [ "$indicateOnLED" == "1" ]; then
    # Check if the LED file is not writable by this script's user with `! -w`:
    if [ ! -w "$led" ]; then
	echo "[ibackupClient] Running chown $USER $led"
	sudo chown "$USER" "$led"
    fi
    if [ ! -w "$ledTrigger" ]; then
	echo "[ibackupClient] Running chown $USER $ledTrigger"
	sudo chown "$USER" "$ledTrigger"
    fi

    if [ ! -w "$led1" ]; then
	echo "[ibackupClient] Running chown $USER $led1"
	sudo chown "$USER" "$led1"
    fi
    if [ ! -w "$ledTrigger1" ]; then
	echo "[ibackupClient] Running chown $USER $ledTrigger1"
	sudo chown "$USER" "$ledTrigger1"
    fi

    # Indicate the program is running in general by turning off led1
    echo 0 > "$led1"
    # Trap for resetting led1 to normal when this script exits
    oldTrap="echo \"[ibackupClient] Resetting led1 to normal\" ; echo mmc0 > \"$ledTrigger1\""
    trap "$oldTrap" SIGINT SIGTERM EXIT
fi

# Prepare PID tables #
backupPID=()
udidTableKeys=$(python3 "$scriptDir/udidToFolderLookupTable.py" "" 0 1)
readarray -t udidTableKeysArray <<< "$udidTableKeys" # This reads {a newline-delimited array of strings} out of a string and into an array. `-t` to strip newlines. ( https://www.javatpoint.com/bash-split-string#:~:text=In%20bash%2C%20a%20string%20can,the%20string%20in%20split%20form. , https://stackoverflow.com/questions/41721847/readarray-t-option-in-bash-default-behavior )

for i in "${udidTableKeysArray[@]}"
do
    backupPID+=('') # No PID yet
done
# #

# Run usbmuxd and wait for devices to connect. When they do, identify them as one of the users in udidToFolderLookupTable.py and then check if a backup has been made today. If a backup hasn't been made, start the backup. #

# https://stackoverflow.com/questions/39239379/add-timestamp-to-teed-output-but-not-original-output
# Usage: `echo "test" | parseOutput`
function parseOutput () {
    # https://stackoverflow.com/questions/1167746/how-to-assign-a-heredoc-value-to-a-variable-in-bash : "Making sure to delimit starting END_HEREDOC with single-quotes. This will prevent the content of the heredoc from being expanded, so dont-execute-this [something like `$(dont-execute-this)` within the heredoc contents] will not be executed."
    local regex=$(
cat <<'END_HEREDOC'
^(\[[0-9]*:[0-9]*:[0-9]*\.[0-9]*\]\[[0-9]*\] )?Got serial '([^\']*)' for device .*$
END_HEREDOC
)

    while read data; do
	echo "${data}"

	set +e
	# Check if `data` indicates that an iOS device was plugged in:
	#if [ ! -z "$(grep -E "$regex")" ]; then
	if [[ $data =~ $regex ]]; then
	    # matched
            local udid="${BASH_REMATCH[2]}" # Get second capture group in the regex ( https://stackoverflow.com/questions/1891797/capturing-groups-from-a-grep-regex )
	    echo "[ibackupClient] Device found: $udid"
	    # Add dash at the 8th position of the udid string ( https://www.unix.com/shell-programming-and-scripting/149658-insert-character-particular-position.html )
	    udid="$(echo "$udid" | sed 's/./&-/8')"

	    # Spawn background process to back it up only if not already running
	    local skip=0 # assume 0
	    for i in "${udidTableKeysArray[@]}"
	    do
		if [ "$i" == "$udid" ]; then
		    # Found it
		    if [ "${backupPID[index]}" != "" ]; then
			# Running already, don't run
			echo "[ibackupClient] Backup background process for $udid is already running, not spawning a new one."
			skip=1
		    fi
		fi
	    done
	    if [ "$skip" == "1" ]; then
		continue
	    fi

	    dest="$dest" udid="$udid" useLocalDiskThenTransfer="$useLocalDiskThenTransfer" firstTime="$firstTime" downloadFromServerFirst="$downloadFromServerFirst" bash ibackupClient_doBackup.sh & # Spawn background process
	    #source ibackupClient_doBackup.sh

	    # Save background process's PID
	    THE_PID=$!

	    myhandler() {
		echo "[ibackupClient] sigchld received"

		# wait only for the pid terminated
		# https://unix.stackexchange.com/questions/344582/discriminate-between-chld-sub-shells-in-trap-function
		for job in `jobs -p`; do
		    echo "[ibackupClient] PID => ${job}"
		    if ! wait ${job} ; then
			local exitCode="$?"
			if [ "$exitCode" == "0" ]; then
			    echo "[ibackupClient] PID ${job} succeeded with exit code $exitCode"
			else
			    echo "[ibackupClient] PID ${job} failed with exit code $exitCode"
			fi
			# echo "At least one test failed with exit code => $?" ;
			# EXIT_CODE=1;
			
			# "Remove" it from the array
			local i=0
			local found=0 # assume 0
			for pid in ${backupPID[*]}; do
			    if [ "$pid" == "${job}" ]; then
				backupPID[i]=""
				found=1
				break
			    fi
			    i=$((i+1))
			done
			if [ "$found" == "0" ]; then
			    echo "[ibackupClient] Error: PID ${job} not found in backupPID array. Continuing anyway..."
			fi
		    fi
		done

		# # wait for all pids
		# for pid in ${backupPID[*]}; do
		#     if [ "$pid" != "" ]; then
		# 	wait $pid
		#     fi
		# done
	    }
	    # When the subprocess terminates, we want to be notified:
	    trap myhandler CHLD
	    # When this script terminates, we want to stop the subprocesses:
	    trap 'kill $(jobs -p) ; $oldTrap' SIGINT SIGTERM EXIT # https://stackoverflow.com/questions/360201/how-do-i-kill-background-processes-jobs-when-my-shell-script-exits

	    local found=0 # assume 0
	    for i in "${udidTableKeysArray[@]}"
	    do
		if [ "$i" == "$udid" ]; then
		    # Found it
		    backupPID[index]="$THE_PID"
		    found=1
		fi
	    done
	    if [ "$found" == "0" ]; then
		echo "[ibackupClient] Error: backup background process for $udid couldn't be saved as running. Continuing anyway..."
	    fi
	fi

	set -e
    done
}

# Fire up the beast (usbmuxd also spawns its own stuff) which grabs network devices but is also using sudo so we can access USB
# NOTE: `parseOutput` doesn't run in the background with `&` here since trapping doesn't seem to work unless you don't run in the background ( https://stackoverflow.com/questions/43545512/unable-to-trap-ctrl-c-to-exit-function-exit-bash-script ) :
sudo `which usbmuxd` --foreground -v 2>&1 | parseOutput # This can be either "regular" usbmuxd (which doesn't seem to support WiFi comms properly) or usbmuxd2, based on the shell.nix used in the shebang. (So we want usbmuxd since we are using USB from the client here instead of WiFi backup.)

#sleep 5
#wait # https://stackoverflow.com/questions/26858344/trap-not-working-in-shell-script

# Now we wait for users to connect by checking the output of usbmuxd using the `parseOutput` function called above.
# #
