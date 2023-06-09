#! /usr/bin/env nix-shell
#! nix-shell -i bash ./shell.nix

# There are two computers involved here: the client and the server. The client is the one making the backups of the iOS devices, and the server is the one receiving the backup data from the client over sshfs.
# 1. The client must make an ssh key using `ssh-keygen -t rsa`
# 2. Make a new user on the server specifically for sshfs access (it will be able to be SSH'ed into normally as well) and add udo 	  1. `sudo useradd iosbackup_usbmuxd`
	  2. `sudo usermod -a -G iosbackup iosbackup_usbmuxd`
# Copy the ssh key to the server: `ssh -i ~/.ssh/mykey user@host`

# Grab config
scriptDir="$(dirname "${BASH_SOURCE[0]}")"
source "$scriptDir/../config.sh"

# Bind sshfs
#sshfs
