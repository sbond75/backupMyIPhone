#! /usr/bin/env nix-shell
#! nix-shell -i bash ./shell_new_libimobiledevice.nix

# NOTE: For setup, run these commands on the client (assumed to be a Raspberry Pi):
# (Set up SSH as needed, wpa_supplicant, etc.)
# sudo apt update && sudo apt upgrade
# sh <(curl -L https://nixos.org/nix/install) --daemon  # Installs nix
# git clone --recursive https://github.com/sbond75/backupMyIPhone
# Nvm: {
# sudo apt-get install smbclient
# sudo apt-get install cifs-utils
# }
# sudo apt install lftp
# sudo apt-get install curlftpfs
# # Transfer the certificate from server into whatever you put in config.sh for `config__certPath`, then test out your connection using this command, replacing `usernameHere_ftp` with the FTP username (run `source config.sh` first):
# lftp -d -u usernameHere_ftp -e 'set ftp:ssl-force true' -e 'set ssl:ca-file '"$config__certPath ; set ssl:check-hostname false;" $config__host  # FTP test command

if [ "$(whoami)" != "pi" ]; then
    echo 'This script must be run as the `pi` user. Exiting.'
    exit 1
fi

ranWithTeeAlready="$1" # Internal use, leave empty

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
    echo "[ibackup] Running with tee to logfile $logfile"
    bash "$0" "1" 2>&1 | tee_with_timestamps "$logfile"
    exit
fi
# #






# Run usbmuxd and wait for devices to connect. When they do, identify them as one of the users in udidToFolderLookupTable.py and then check if a backup has been made today. If a backup hasn't been made, start the backup. #

# https://stackoverflow.com/questions/39239379/add-timestamp-to-teed-output-but-not-original-output
# Usage: `echo "test" | tee_with_timestamps "file.txt"`
function parseOutput () {
    local logfile=$1
    while read data; do
	# Check if `data` indicates that an iOS device was plugged in:
	
	echo "${data}"
    done
}

# Fire up the beast (usbmuxd also spawns its own stuff) which grabs network devices but is also using sudo so we can access USB
sudo `which usbmuxd` -v 2>&1 | parseOutput & # This can be either "regular" usbmuxd (which doesn't seem to support WiFi comms properly) or usbmuxd2, based on the shell.nix used in the shebang. (So we want usbmuxd since we are using USB from the client here instead of WiFi backup.)

sleep 5

# Now we wait for users to connect by checking the output of usbmuxd:

# #

# Mount fuse filesystem for server's vsftpd to use
#curlftpfs "ftp://$username:$password@$config__host" "$mountPoint"
