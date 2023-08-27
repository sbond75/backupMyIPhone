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
# sudo apt-get install curlftpfs
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
firstTime="$2" # Set to 1 to enable backup encryption interactively

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
    bash "$0" "$logfile" "$firstTime" 2>&1 | tee_with_timestamps "$logfile"
    exit
fi
# #






function serverCmd_impl() {
    # `-v` for verbose (to show why connections fail, if they do)
    # `-N` to exit after sending ( https://unix.stackexchange.com/questions/332163/netcat-send-text-to-echo-service-read-reply-then-exit )
    netcat -N -v "$config__host" "$config__serverCommands_port" <<< "$1" # (`<<<` is called a "here string" ( https://askubuntu.com/questions/443227/sending-a-simple-tcp-message-using-netcat , https://stackoverflow.com/questions/16045139/redirector-in-ubuntu )
}

function serverCmd() {
    local retryTillSuccess="$2"

    if [ "$retryTillSuccess" == "1" ]; then
	# Keep trying till it succeeds, since this is important:
	local exitCode=1
	while [ "$exitCode" != 0 ]; do
	    serverCmd_impl "$1"
	    exitCode="$?"
	    if [ "$exitCode" == "0" ]; then
		break
	    else
		echo "[ibackupClient] Running command $1 on server failed with exit code $exitCode. Retrying in 30 seconds..."
	    fi
	    sleep 30
	done
    else
	serverCmd_impl "$1"
    fi
}

function urlencode() {
    # https://askubuntu.com/questions/53770/how-can-i-encode-and-decode-percent-encoded-strings-on-the-command-line , https://stackoverflow.com/questions/40557606/how-to-url-encode-in-python-3
    python3 -c "import urllib.parse; import sys; print(urllib.parse.quote(  sys.argv[1] if len(sys.argv) > 1 else sys.stdin.read()[0:-1], safe=''))" "$1"
}

# Make an array for all the devices' backup statuses (whether they were backed up today or not) per UDID
wasBackedUp=()
wasBackedUp_times=() # time strings for last backup, or "" for no backup at all yet
# Nvm: this is for users, not UDIDs: #
# source "$scriptDir/allConfiguredFTPUsers.sh" # Puts users into `users` array
# for i in "${users[@]}"
# do
#     wasBackedUp+=(0) # 0 for false
# done

# function wasBackedUp_() {
#     local usernameWithFTPSuffix="$1"
#     local index = 0
#     for i in "${users[@]}"
#     do
# 	if [ "$i" == "$usernameWithFTPSuffix" ]; then
# 	    # Found it
# 	    echo "${wasBackedUp[index]}"
# 	    return
# 	fi
# 	let index=${index}+1 # (`let` is for arithmetic -- https://stackoverflow.com/questions/6723426/looping-over-arrays-printing-both-index-and-value , https://stackoverflow.com/questions/18704857/bash-let-statement-vs-assignment )
#     done
#     # If we get here, it wasn't found... return "2" instead
#     echo 2
# }

# function setWasBackedUp_() {
#     local usernameWithFTPSuffix="$1"
#     local setTo="$2"
#     local index = 0
#     for i in "${users[@]}"
#     do
# 	if [ "$i" == "$usernameWithFTPSuffix" ]; then
# 	    # Found it
# 	    wasBackedUp[index]="$setTo"
# 	    echo 1 # success
# 	    return
# 	fi
# 	let index=${index}+1 # (`let` is for arithmetic -- https://stackoverflow.com/questions/6723426/looping-over-arrays-printing-both-index-and-value , https://stackoverflow.com/questions/18704857/bash-let-statement-vs-assignment )
#     done
#     # If we get here, it wasn't found... return "2" instead
#     echo 2
# }
# End nvm #
# Actual stuff: #
udidTableKeys=$(python3 "$scriptDir/udidToFolderLookupTable.py" "" 0 1)
readarray -t udidTableKeysArray <<< "$udidTableKeys" # This reads {a newline-delimited array of strings} out of a string and into an array. `-t` to strip newlines. ( https://www.javatpoint.com/bash-split-string#:~:text=In%20bash%2C%20a%20string%20can,the%20string%20in%20split%20form. , https://stackoverflow.com/questions/41721847/readarray-t-option-in-bash-default-behavior )

for i in "${udidTableKeysArray[@]}"
do
    wasBackedUp+=(0) # 0 for false
    wasBackedUp_times+=("")
done

# Outputs #
wasBackedUp__timeTillNextBackup=
# #
function wasBackedUp_() {
    local udid="$1"
    local index=0
    for i in "${udidTableKeysArray[@]}"
    do
	if [ "$i" == "$udid" ]; then
	    # Found it
	    res="${wasBackedUp[index]}"
	    if [ "$res" == "1" ]; then
		# Check if this is too old
		local now=
		if [ -z "$2" ]; then
		    now="$(date +%s)" # Get time in seconds since UNIX epoch ( https://stackoverflow.com/questions/1092631/get-current-time-in-seconds-since-the-epoch-on-linux-bash )
		else
		    now="$2"
		fi
		local past="${wasBackedUp_times[index]}"
		local inc=$((86400 / 2)) # Seconds in a day divided by 2
		local next=$(($past + $inc))
		wasBackedUp__timeTillNextBackup=$(($next - $now))
		if [ "$now" -ge "$next" ]; then
		    echo "0" # always make this "too old" of a backup, so we report "0" to mean "not backed up"
		else
		    echo "$res" # keep original status
		fi
	    else
		wasBackedUp__timeTillNextBackup=0
		# "Return" it
		echo "$res"
	    fi
	    return
	fi
	let index=${index}+1 # (`let` is for arithmetic -- https://stackoverflow.com/questions/6723426/looping-over-arrays-printing-both-index-and-value , https://stackoverflow.com/questions/18704857/bash-let-statement-vs-assignment )
    done
    # If we get here, it wasn't found... return "2" instead
    echo 2
}

function setWasBackedUp_() {
    local udid="$1"
    local setTo="$2"
    local index = 0
    for i in "${udidTableKeysArray[@]}"
    do
	if [ "$i" == "$udid" ]; then
	    # Found it
	    wasBackedUp[index]="$setTo"

	    local now=
	    if [ -z "$3" ]; then
		now="$(date +%s)" # Get time in seconds since UNIX epoch ( https://stackoverflow.com/questions/1092631/get-current-time-in-seconds-since-the-epoch-on-linux-bash )
	    else
		now="$3"
	    fi

	    wasBackedUp_times[index]="$now"

	    echo 1 # success
	    return
	fi
	let index=${index}+1 # (`let` is for arithmetic -- https://stackoverflow.com/questions/6723426/looping-over-arrays-printing-both-index-and-value , https://stackoverflow.com/questions/18704857/bash-let-statement-vs-assignment )
    done
    # If we get here, it wasn't found... return "2" instead
    echo 2
}
# #

function unmountUser() {
    local mountPoint="$1"

    # Keep trying till it succeeds, since this is important:
    local exitCode=1
    while [ "$exitCode" != 0 ]; do
	echo "[ibackupClient] Unmounting FTP filesystem..."
	fusermount -u "$mountPoint"
	exitCode="$?"
	if [ "$exitCode" == "0" ]; then
	    echo "[ibackupClient] Unmounted FTP filesystem."
	    break
	else
	    echo "[ibackupClient] Unmounting FTP filesystem failed with exit code $exitCode. Retrying in 30 seconds..."
	fi
	sleep 30
    done
}

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
	    # Delay to prevent it not being found
	    local sl=2
	    echo "[ibackupClient] Sleeping for $sl seconds..."
	    sleep $sl
	    # Print device info for reference:
	    ideviceinfo --udid "$udid"
	    # Compare udid to lookup table ignoring dashes
	    local userFolderName=$(python3 "$scriptDir/udidToFolderLookupTable.py" "$udid" 1)
	    echo "[ibackupClient] User folder name: $userFolderName"
	    if [ -z "$userFolderName" ]; then
		echo "Empty name (possibly not found), not able to interface with this device."
		continue
	    fi
	    # Now we know which user this backup should go under.

	    # Check if the device was backed up already
	    local now="$(date +%s)"
	    wasBackedUp_ "$udid" "$now" # for side effects only. Functions in bash can't write to globals in the surrounding bash process if you use a subshell with `$()` ( https://stackoverflow.com/questions/23564995/how-to-modify-a-global-variable-within-a-function-in-bash ). So we pass a parameter for `now` to it here to make it function exactly the same as the call to the same function below used in a subshell:
	    local didBackup=$(wasBackedUp_ "$udid" "$now")
	    if [ "$didBackup" == "2" ]; then
		echo "[ibackupClient] UDID $udid is unknown. Not backing up this device."
		continue
	    elif [ "$didBackup" == "1" ]; then
		local till="$(python3 -c "from sys import argv; print(float(argv[1]) / 3600)" "$wasBackedUp__timeTillNextBackup")" # Convert seconds to hours
		echo "[ibackupClient] Already backed up device ${udid} today (next backup is in at least $till hour(s)). Not backing up now."
		continue
	    else # Assume it is "0" meaning not backed up yet
		local since="$(python3 -c "from sys import argv; print(-float(argv[1]) / 3600)" "$wasBackedUp__timeTillNextBackup")" # Convert seconds to hours (and negate the input seconds)
		echo "[ibackupClient] Preparing to back up device ${udid} now (last backup was $since hour(s) ago)."
	    fi
	    local deviceToConnectTo="$udid"

	    # Mount fuse filesystem for server's vsftpd to use
	    local username="${userFolderName}"'_ftp'
	    local password="$(eval echo '$config__'"$username")"
	    local mountPoint="${config__clientDirectory}/$username"
	    if [ ! -e "$mountPoint" ]; then
		mkdir "$mountPoint"
	    fi
	    # Unmount on ctrl-c or exit if any (in preparation for ideally running this handler *after* the below command) #
	    # Also note that it will only run the trap handler *after* the currently executing function in bash finishes. So if `sleep 30` is currently running and you press ctrl-c`, bash will only respond after the `sleep 30` command finishes ( https://unix.stackexchange.com/questions/387847/bash-script-doesnt-see-sighup )
	    #local oldTrapEnd='kill -s INT "$$" # report to the parent that we have indeed been interrupted' # https://unix.stackexchange.com/questions/386836/why-is-doing-an-exit-130-is-not-the-same-as-dying-of-sigint
	    local oldTrapEnd=''
	    local oldTrap='echo "trap worked 1"; unmountUser $mountPoint ; '"$oldTrapEnd"
	    local signals='EXIT'
	    trap "$oldTrap" $signals # https://superuser.com/questions/1719758/bash-script-to-catch-ctrlc-at-higher-level-without-interrupting-the-foreground , https://askubuntu.com/questions/1464619/run-command-before-script-exits
	    # #
	    echo "[ibackupClient] Mounting FTP filesystem..."
	    # export -f urlencode # https://superuser.com/questions/319538/aliases-in-subshell-child-process : "If you want them to be inherited to sub-shells, use functions instead. Those can be exported to the environment (export -f), and sub-shells will then have those functions defined."
	    # curlftpfs -o "sslv3,cacert=${config__certPath},no_verify_hostname" "$username:$(urlencode "$password")@$config__host" "$mountPoint" # [fixed using urlencode]FIXME: if password has commas it will probably break this `user=` stuff

	    # https://serverfault.com/questions/115307/mount-an-ftps-server-to-a-linux-directory-but-get-access-denied-530-error : "You can try -o ssl"
	    curlftpfs -f -o "ssl,cacert=${config__certPath},no_verify_hostname,user=$username:$password" "$config__host" "$mountPoint" & # FIXME: if password has commas it will probably break this `user=` stuff
	    # By default, curlftpfs runs in the "background" (as a daemon sort of process it seems -- parented to the root PID). You can use `-f` to run it in foreground ( https://linux.die.net/man/1/curlftpfs ), so we run it in foreground so it terminates on exit of this script.
	    # Also note that curlftpfs seems to hang around in the background until `umount` or `fusermount -u` is run on the mount point for FTP, so that might be fine since this script also unmounts the filesystem at exit..

	    local exitCode="$?"
	    if [ "$exitCode" != "0" ]; then
		echo "[ibackupClient] Mounting FTP filesystem failed with exit code $exitCode. Skipping this backup until device is reconnected."

		# Clear trap
		trap - $signals

		continue
	    fi
	    echo "[ibackupClient] Mounted FTP filesystem."

	    if [ "$firstTime" == "1" ]; then
		# Enable encryption
		idevicebackup2 --udid "$deviceToConnectTo" -i encryption on
		local exitCode="$?"
		if [ "$exitCode" != "0" ]; then
		    echo "[ibackupClient] Enabling encryption failed with exit code $exitCode. Skipping this backup until device is reconnected."
		
		    # Clear trap
		    trap - $signals

		    # Unmount that user
		    unmountUser "$mountPoint"

		    continue
		fi
		# Optional (if a password wasn't set)
		read -p "Enable or change backup password (needed to get Health data like steps, WiFi settings, call history, etc. ( https://support.apple.com/en-us/HT205220 )) (y/n)? " -r
		if [[ ! $REPLY =~ ^[Yy]$ ]]
		then
		    idevicebackup2 --udid "$deviceToConnectTo" -i changepw
		    local exitCode="$?"
		    if [ "$exitCode" != "0" ]; then
			echo "[ibackupClient] Setting backup password failed with exit code $exitCode. Skipping this backup until device is reconnected."
		
			# Clear trap
			trap - $signals

			# Unmount that user
			unmountUser "$mountPoint"

			continue
		    fi
		else
		    :
		fi
		firstTime=0 # Already enabled from now on

		set +e
	    fi

	    # "Stop backup" but unsuccessfully on ctrl-c or exit if any (in preparation for ideally running this handler *after* the below command) #
	    trap 'echo "trap worked 2"; serverCmd "finishBackupUnsuccessful" 1 ; '"$oldTrap" $signals # Add a new trap to the existing one without overwriting it
	    #trap 'echo "trap worked 2"; serverCmd "finishBackupUnsuccessful" 1' INT EXIT
	    # #
	    # Prepare the server for backup:
	    echo "[ibackupClient] Preparing server for backup..."
	    serverCmd "startBackup"
	    local exitCode="$?"
	    if [ "$exitCode" != "0" ]; then
		echo "[ibackupClient] Preparing server for backup failed with exit code $exitCode. Skipping this backup until device is reconnected."
		
		# Clear trap
		trap - $signals

		# Unmount that user
		unmountUser "$mountPoint"

		continue
	    fi
	    echo "[ibackupClient] Prepared server for backup."

	    # Perform the backup:
	    echo "[ibackupClient] Starting backup."
	    idevicebackup2 --udid "$deviceToConnectTo" backup "$dest"
	    local exitCode="$?"
	    echo "[ibackupClient] Backup finished with exit code ${exitCode}."

	    # Tell the server we are done backing up:
	    echo "[ibackupClient] Telling server backup is done..."
	    if [ "$exitCode" == "0" ]; then
		serverCmd "finishBackup" 1
	    else
		serverCmd "finishBackupUnsuccessful" 1
	    fi
	    echo "[ibackupClient] Told server backup is done."

	    # Clear trap to original item (to unmount)
	    trap "$oldTrap" $signals

	    # Unmount that user
	    unmountUser "$mountPoint"

	    # Clear trap
	    trap - $signals

	    # Save backup success status
	    echo "[ibackupClient] Setting backup status as backed up for device $udid of user ${userFolderName}."
	    local now="$(date +%s)"
	    setWasBackedUp_ "$udid" 1 "$now" # for side effects only; then we do the below in a subshell:
	    local found=$(setWasBackedUp_ "$udid" 1 "$now")
	    if [ "$found" == "2" ]; then
		# Not found, error
		echo "[ibackupClient] Couldn't mark UDID $udid as completed. Ignoring error..."
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
