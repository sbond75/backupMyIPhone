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






# Grab functions (and config which was actually already grabbed)
source ibackupClient_common.sh

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
	    #udid="$udid" bash ibackupClient_doBackup.sh & # Spawn background process
	    source ibackupClient_doBackup.sh
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
