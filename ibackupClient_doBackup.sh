# Grab functions and config
source ibackupClient_common.sh

serverCmd_startBackup_retval=0 # read from this after calling the below function; if it is 1 it was unsuccessful.
function serverCmd_startBackup() {
    local signals="$1"
    local oldTrap="$2"

    if [ ! -z "$signals" ]; then
	# "Stop backup" but unsuccessfully on ctrl-c or exit if any (in preparation for ideally running this handler *after* the below command) #
	trap 'echo "trap worked 2"; serverCmd "finishBackupUnsuccessful" 1 '"$udid"' ; '"$oldTrap" $signals # Add a new trap to the existing one without overwriting it
	#trap 'echo "trap worked 2"; serverCmd "finishBackupUnsuccessful" 1' INT EXIT
	# #
    fi
    # Prepare the server for backup:
    echo "[ibackupClient] Preparing server for backup..."
    serverCmd "startBackup" 0 "$udid"
    local exitCode="$?"
    if [ "$exitCode" != "0" ]; then
	echo "[ibackupClient] Preparing server for backup failed with exit code $exitCode. Skipping this backup until device is reconnected."

	if [ "$useLocalDiskThenTransfer" != "1" ]; then
	    # Clear trap
	    trap - $signals

	    # # Grab username from udid to lookup table ignoring dashes
	    # local userFolderName=$(python3 "$scriptDir/udidToFolderLookupTable.py" "$udid" 1)
	    # local username="${userFolderName}"'_ftp'

	    # Unmount that user
	    # local mountPoint="${config__clientDirectory}/$username"
	    unmountUser "$mountPoint"
	fi

	#continue
	serverCmd_startBackup_retval=1
	return
    fi
    echo "[ibackupClient] Prepared server for backup."
    serverCmd_startBackup_retval=0
}

# LED indicator stuff #
# (`led` and `ledTrigger` variables are from `ibackupClient_common.sh`.)

addedLEDTrap=0 # 0 if not, 1 if did add it

function resetToDefault_LED() {
    if [ ! -z "$indicateOnLED" ]; then
	echo mmc0 > "$ledTrigger"
    fi
}

function installLEDTrap() {
    if [ "$addedLEDTrap" == "0" ]; then
	# Trap to reset LED to default
	local signals='EXIT'
	local stopBlink='if [ ! -z "$BLINK_JOB_PID" ]; then kill "$BLINK_JOB_PID" ; fi'
	trap "echo \"[ibackupClient] Resetting led to normal\" ; $stopBlink ; resetToDefault_LED ; $oldTrap" $signals

	addedLEDTrap=1
    fi
}

BLINK_JOB_PID=
function preStartingBackup_LED() {
    local oldTrap="$1"

    if [ ! -z "$indicateOnLED" ]; then
	# Blink the LED
	{ while true; do echo 0 > "$led" && sleep 0.5 && echo 1 > "$led" ; done } &
	BLINK_JOB_PID=$!

	# Trap to reset LED to default
	installLEDTrap
    fi
}

function startingBackup_LED() {
    local oldTrap="$1"

    if [ ! -z "$indicateOnLED" ]; then
	# Solid LED to indicate backing up
	echo 1 > "$led"

	# Trap to reset LED to default
	installLEDTrap
    fi
}

function finishedBackup_LED() {
    local oldTrap="$1"

    if [ ! -z "$indicateOnLED" ]; then
	# Turn off LED to indicate finished backup
	echo 0 > "$led"

	# Trap to reset LED to default
	installLEDTrap
    fi
}
# #

function doBackup() {
    # # Delay to prevent it not being found
    # #local sl=2
    # local sl=8
    # echo "[ibackupClient] Sleeping for $sl seconds..."
    # sleep $sl
    # Print device info for reference:
    ideviceinfo --udid "$udid"
    # Compare udid to lookup table ignoring dashes
    local userFolderName=$(python3 "$scriptDir/udidToFolderLookupTable.py" "$udid" 1)
    echo "[ibackupClient] User folder name: $userFolderName"
    if [ -z "$userFolderName" ]; then
	echo "[ibackupClient] Empty name (possibly not found), not able to interface with this device."
	#continue
	return
    fi
    # Now we know which user this backup should go under.

    # Check if the device was backed up already
    local now="$(date +%s)"
    wasBackedUp_ "$udid" "$now" # for side effects only. Functions in bash can't write to globals in the surrounding bash process if you use a subshell with `$()` ( https://stackoverflow.com/questions/23564995/how-to-modify-a-global-variable-within-a-function-in-bash ). So we pass a parameter for `now` to it here to make it function exactly the same as the call to the same function below used in a subshell:
    local didBackup=$(wasBackedUp_ "$udid" "$now")
    if [ "$didBackup" == "2" ]; then
	echo "[ibackupClient] UDID $udid is unknown. Not backing up this device."
	#continue
	return
    elif [ "$didBackup" == "s" ] || [ "$didBackup" == "f" ]; then # started or finished
	local till="$(python3 -c "from sys import argv; print(float(argv[1]) / 3600)" "$wasBackedUp__timeTillNextBackup")" # Convert seconds to hours
	echo "[ibackupClient] Already backed up device ${udid} today (status $didBackup) (next backup is in at least $till hour(s)). Not backing up now."
	#continue
	return
    else # Assume it is "0" meaning not backed up yet
	local since="$(python3 -c "from sys import argv; print(-float(argv[1]) / 3600)" "$wasBackedUp__timeTillNextBackup")" # Convert seconds to hours (and negate the input seconds)
	echo "[ibackupClient] Preparing to back up device ${udid} now (last backup was $since hour(s) ago)."
    fi
    local deviceToConnectTo="$udid"

    # Show the pre-starting backup status on the LED (assuming raspberry pi)
    preStartingBackup_LED ''

    # Mount fuse filesystem for server's vsftpd to use
    username="${userFolderName}"'_ftp'
    local password="$(eval echo '$config__'"$username")"
    mountPoint="${config__clientDirectory}/$username"
    if [ ! -e "$mountPoint" ] && [ "$useLocalDiskThenTransfer" != "1" ]; then
	set -e
	mkdir "$mountPoint"
	set +e
    fi
    if [ "$useLocalDiskThenTransfer" != "1" ] || [ "$config__syncMethod" == "rsync" ]; then
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
	echo curlftpfs -f -o "ssl,cacert=${config__certPath},no_verify_hostname,user=$username:$password" "$config__host" "$mountPoint" '&'
	curlftpfs -f -o "ssl,cacert=${config__certPath},no_verify_hostname,user=$username:$password" "$config__host" "$mountPoint" & # FIXME: if password has commas it will probably break this `user=` stuff
	# By default, curlftpfs runs in the "background" (as a daemon sort of process it seems -- parented to the root PID). You can use `-f` to run it in foreground ( https://linux.die.net/man/1/curlftpfs ), so we run it in foreground so it terminates on exit of this script.
	# Also note that curlftpfs seems to hang around in the background until `umount` or `fusermount -u` is run on the mount point for FTP, so that might be fine since this script also unmounts the filesystem at exit..

	local exitCode="$?" # FIXME: this probably won't work since it is run in the background with `&` above..
	if [ "$exitCode" != "0" ]; then
	    echo "[ibackupClient] Mounting FTP filesystem failed with exit code $exitCode. Skipping this backup until device is reconnected."

	    # Clear trap
	    trap - $signals

	    #continue
	    return
	fi
	echo "[ibackupClient] Mounted FTP filesystem."
	destFull="$dest/${userFolderName}_ftp"
	# if [ "$firstTime" == "1" ]; then
	#     # Use sudo to make destination directory
	#     sudo mkdir -p "$destFull"
	# fi
    #else
    fi
    if [ "$useLocalDiskThenTransfer" == "1" ]
	# Local disk to use
	echo "[ibackupClient] After downloading server contents, will back up to local location $config__localDiskPath (on disk $config__localDisk) and then transfer to server."
	destFull="$config__localDiskPath/${userFolderName}"

	# Mount if needed
	local madeDiskMount=0 # assume 0
	if [ ! -z "$config__localDisk" ]; then # (optional)
	    #mountpoint "$config__localDisk" || { echo "Error: backup destination drive not mounted. Exiting."; exit 1; }
	    local failed=0 # assume 0
	    mountpoint "$config__localDisk" || {
		# Use sudo to make disk directory; then mount it
		madeDiskMount=1 ; echo "[ibackupClient] Mounting $config__localDisk from $config__localDiskDevice" && sudo mkdir -p "$config__localDisk" && sudo mount "$config__localDiskDevice" "$config__localDisk" ; } || { echo "Error: failed to mount backup destination drive. Not backing up this device for now."; failed=1; }
	    if [ "$failed" == "1" ]; then
		return
	    fi
	fi

	set -e
	if [ "$firstTime" == "1" ] || [ "$madeDiskMount" == "1" ]; then
	    # Use sudo to make destination directory
	    sudo mkdir -p "$destFull"
	    # Chown it
	    sudo chown -R pi "$config__localDiskPath"
	else
	    mkdir -p "$destFull"
	fi

	# Prepare to download the backup from the server first
	# Technically `remoteDir=.` is used further a few lines below (it used to be commented out) and this directly below getting sent to the server is what prepares the home folder /home/userNameHere_ftp to be a bind mount to the actual path. This is instead of `remoteDir=`[the actual path].
	local signals='EXIT'
	local oldTrap=''
	serverCmd_startBackup "$signals" "$oldTrap"
	if [ "$serverCmd_startBackup_retval" == "1" ]; then
	    # Failed
	    return
	fi

	if [ "$downloadFromServerFirst" == "1" ]; then
	# Download backup from server first
	echo "[ibackupClient] Downloading server backup contents for $username to $destFull..."
	localDir="$destFull"
	remoteDir="."
	#remoteDir="$config__drive/home/$userFolderName/@iosBackups" # we use this instead of `.` in case the start backup command is slow to respond..
	if [ "$config__syncMethod" == "lftp" ]; then
	lftp -e "
    set ftp:ssl-force true
    set ssl:ca-file $config__certPath
    set ssl:check-hostname false
    set xfer:timeout 60
    set net:timeout 60
    open $config__host
    user $username $password
    lcd $localDir
    mirror --continue --delete --verbose $remoteDir $localDir
    bye
    " # note: `xfer:timeout` is set to 60 so it doesn't hang forever if network cuts out. `net:timeout` is set in case it is needed.. ( https://lftp.yar.ru/lftp-man.html )
	exitCode="$?"
	else
	    # Use rsync from the curlftpfs mount to `$localDir`
	    echo rsync --sparse --archive --verbose --human-readable --progress "$mountPoint" "$localDir"
	    rsync --sparse --archive --verbose --human-readable --progress "$mountPoint" "$localDir"
	    exitCode="$?"
	fi
	echo "[ibackupClient] Finished transfer of backup from server with exit code ${exitCode}."
	else
	    echo "[ibackupClient] Skipping transfer of backup from server due to command-line config."
	fi
	set +e
    fi

    if [ "$firstTime" == "1" ]; then
	# Pair
	idevicepair --udid "$deviceToConnectTo" pair
	local exitCode="$?"
	local i=2
	while [ "$exitCode" != "0" ]; do	    
	    # Delay to prevent it not being found
	    #local sl=2
	    local sl=8
	    echo "[ibackupClient] Sleeping for $sl seconds..."
	    sleep $sl

	    echo "[ibackupClient] Retrying pair for $deviceToConnectTo after failing with exit code $exitCode (attempt $i)"
	    idevicepair --udid "$deviceToConnectTo" pair
	    exitCode="$?"
	    i=$((i+1))
	done

	# Enable encryption
	forceSuccess=0 # assume 0
	function processOutput() {
	while read data; do
	    echo "${data}"

	    local regex=$(
cat <<'END_HEREDOC'
^ERROR: Backup encryption is already enabled\. Aborting\.$
END_HEREDOC
)
	    if [[ $data =~ $regex ]]; then
		# Consider it a success still
		forceSuccess=1
	    else
		:
	    fi
	done
	}
	idevicebackup2 --udid "$deviceToConnectTo" -i encryption on | processOutput
	local exitCode="$?"
	if [ "$exitCode" != "0" ] && [ "$forceSuccess" == "0" ]; then
	    echo "[ibackupClient] Enabling encryption failed with exit code $exitCode. Skipping this backup until device is reconnected."

	    if [ "$useLocalDiskThenTransfer" != "1" ]; then
		# Clear trap
		trap - $signals

		# Unmount that user
		unmountUser "$mountPoint"
	    fi

	    #continue
	    return
	fi
	if [ "$exitCode" == "0" ] && [ "$forceSuccess" == "0" ]; then # i.e. if *just* enabled encryption
	    # Optional (if a password wasn't set)
	    read -p "Enable or change backup password (needed to get Health data like steps, WiFi settings, call history, etc. ( https://support.apple.com/en-us/HT205220 )) (y/n)? " -r
	    if [[ ! $REPLY =~ ^[Yy]$ ]]
	    then
		idevicebackup2 --udid "$deviceToConnectTo" -i changepw
		local exitCode="$?"
		if [ "$exitCode" != "0" ]; then
		    echo "[ibackupClient] Setting backup password failed with exit code $exitCode. Skipping this backup until device is reconnected."

		    if [ "$useLocalDiskThenTransfer" != "1" ]; then
			# Clear trap
			trap - $signals

			# Unmount that user
			unmountUser "$mountPoint"
		    fi

		    #continue
		    return
		fi
	    else
		:
	    fi
	fi
	firstTime=0 # Already enabled from now on

	set +e
    fi

    # Start backup if needed
    if [ "$useLocalDiskThenTransfer" != "1" ]; then
	serverCmd_startBackup "$signals" "$oldTrap"
	if [ "$serverCmd_startBackup_retval" == "1" ]; then
	    # Failed
	    return
	fi
    fi

    # Perform the backup:
    echo "[ibackupClient] Starting backup."
    # Show the starting backup status on the LED (assuming raspberry pi)
    startingBackup_LED "$oldTrap"
    # FIXME: all the output from usbmuxd may fill up the pipe, since our `read data` calls (at the top of this `function parseOutput ()` function) aren't being done *until* this area of the while loop finishes (maybe run all this below in the background with `&`?)
    idevicebackup2 --udid "$deviceToConnectTo" backup "$destFull"
    local exitCode="$?"
    echo "[ibackupClient] Backup finished with exit code ${exitCode}."

    if [ "$exitCode" == "0" ] && [ "$useLocalDiskThenTransfer" == "1" ]; then
	# Need to transfer backup to server now
	echo "[ibackupClient] Beginning transfer of backup to server for $username from $destFull..."
	localDir="$destFull"
	remoteDir="."
	#remoteDir="$config__drive/home/$userFolderName/@iosBackups"
	if [ "$config__syncMethod" == "lftp" ]; then
	# https://stackoverflow.com/questions/5245968/syntax-for-using-lftp-to-synchronize-local-folder-with-an-ftp-folder
	# lftp -f "
    # open $config__host
    # user $username $password
    # lcd $localDir
    # mirror --continue --delete --verbose $remoteDir $localDir
    # bye
    # "
	# The key: `--reverse` here goes from "Local directory to FTP server directory":
	# (Tip: to turn on debug output, put `debug` as the first command below:)
	lftp -e "
    set ftp:ssl-force true
    set ssl:ca-file $config__certPath
    set ssl:check-hostname false
    set xfer:timeout 60
    set net:timeout 60
    open $config__host
    user $username $password
    lcd $localDir
    mirror --continue --reverse --delete --verbose $localDir $remoteDir
    bye
    " # note: `xfer:timeout` is set to 60 so it doesn't hang forever if network cuts out. `net:timeout` is set in case it is needed.. ( https://lftp.yar.ru/lftp-man.html )
	exitCode="$?"
	else
	    # Use rsync from `$localDir` to the curlftpfs mount
	    rsync --sparse --archive --verbose --human-readable --progress "$localDir" "$mountPoint"
	    exitCode="$?"
	fi
	echo "[ibackupClient] Finished transfer of backup to server with exit code ${exitCode}."
    fi

    # Tell the server we are done backing up:
    echo "[ibackupClient] Telling server backup is done..."
    if [ "$exitCode" == "0" ]; then
	serverCmd "finishBackup" 1 "$udid"
	echo "[ibackupClient] Told server backup is done successfully."
    else
	serverCmd "finishBackupUnsuccessful" 1 "$udid"
	echo "[ibackupClient] Told server backup is done unsuccessfully."
    fi

    if [ "$useLocalDiskThenTransfer" != "1" ]; then
	# Clear trap to original item (to unmount)
	trap "$oldTrap" $signals

	# Unmount that user
	unmountUser "$mountPoint"

	# Clear trap
	trap - $signals
    fi

    # Save backup success status
    echo "[ibackupClient] Setting backup status as backed up for device $udid of user ${userFolderName}."
    local now="$(date +%s)"
    setWasBackedUp_ "$udid" f "$now" # for side effects only; then we do the below in a subshell:
    local found=$(setWasBackedUp_ "$udid" f "$now")
    if [ "$found" == "2" ]; then
	# Not found, error
	echo "[ibackupClient] Couldn't mark UDID $udid as completed. Ignoring error..."
    fi

    # Show the finished status on the LED (assuming raspberry pi)
    finishedBackup_LED ''
}

doBackup
