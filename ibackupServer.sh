#! /usr/bin/env nix-shell
#! nix-shell shell_ibackupServer.nix -i bash

##! nix-shell -i bash -p netcat-gnu samba

# SETUP ######################################################################################
# NOTE: For setup, run these commands on the server (assumed to be running NixOS):
# cd /etc/nixos
# sudo mkdir openssl_certificates
# cd openssl_certificates
# sudo chmod o-rx .
# sudo openssl req -x509 -nodes -days 358000 -newkey rsa:4096 -keyout vsftpd.pem -out vsftpd.pem

# Also need to add this to /etc/nixos/configuration.nix on NixOS: {
#   # vsftpd for FTP #
#   services.vsftpd = {
#     enable = true;
# #   cannot chroot && write
# #    chrootlocalUser = true;
#     writeEnable = true;
#     localUsers = true;
#     userlist = [ "user1Here_iosbackup_ftp" "user2Here_iosbackup_ftp" ]; # set passwords of each using sudo passwd `usernameHere`
#     userlistEnable = true;
#     extraConfig = ''pasv_min_port=56250
# pasv_max_port=56260

# # This option specifies the location of the RSA certificate to use for SSL
# # encrypted connections.
# #rsa_cert_file=/etc/ssl/certs/ssl-cert-snakeoil.pem
# #rsa_private_key_file=/etc/ssl/private/ssl-cert-snakeoil.key
# rsa_cert_file=/etc/nixos/openssl_certificates/vsftpd.pem
# rsa_private_key_file=/etc/nixos/openssl_certificates/vsftpd.pem
# ssl_enable=YES
# allow_anon_ssl=NO
# force_local_data_ssl=YES
# force_local_logins_ssl=YES
# ssl_tlsv1=YES
# ssl_sslv2=NO
# ssl_sslv3=NO
# require_ssl_reuse=NO
# ssl_ciphers=HIGH
# ''; # https://stackoverflow.com/questions/57038205/running-an-ftp-server-on-nixos     # Then generate openssl keys: cd openssl_certificates && sudo openssl req -x509 -nodes -days 358000 -newkey rsa:4096 -keyout vsftpd.pem -out vsftpd.pem    # Then, on the client, to grab the SSL certificate use this, filling in CERTS_PATH with the path to a folder for certificates (anywhere but with good perms or something), and also set SERVERNAME with some file name and HOST with its ip: `PORTNUMBER=21 ; </dev/null openssl s_client -starttls ftp -connect $HOST:$PORTNUMBER -servername $SERVERNAME     | openssl x509 > "$CERTS_PATH/$SERVERNAME.cert"`. Then, to connect: `sudo apt install lftp` and then (HOST is the ip address): `lftp -d -u user1Here_iosbackup_ftp -e 'set ftp:ssl-force true' -e 'set ssl:ca-file '"$CERTS_PATH/$SERVERNAME.cert ; set ssl:check-hostname false;" $HOST
# # Note: to view certificate from server, where HOST is the ip address: openssl s_client -connect $HOST:21 -starttls ftp
#   };
#   # #
# } -- end of configuration stuff. Then open ports on NixOS's firewall for vsftpd and for this ibackupServer.sh script (put this in configuration.nix under `networking.firewall.allowedTCPPorts = [`): {
# # For vsftpd (for FTP) ( https://stackoverflow.com/questions/57038205/running-an-ftp-server-on-nixos )
#   20 21 # "Just a bit of background: A typical FTP server listens on TCP ports 20 for data and 21 for command (also known as control port). Connection establishment and exchange of command parameters are done over port 21. FTP connections support two methods: active and passive modes. During connection establishment in active mode, the server initiates a connection from its port 20 (data) to the client. In passive mode, the server dedicates a random data port for each client session, and notifies the client about the port. The client then initiates a connection to the server's random port." ( https://www.xmodulo.com/secure-ftp-service-vsftpd-linux.html )
#   # Configurable ports for vsftpd to use (for FTP) -- these correspond to the range in `extraConfig` under the `services.vsftpd` part of this configuration.nix file higher up in the file:
#   56250 56251 56252 56253 56254 56255 56256 56257 56258 56259 56260 # https://stackoverflow.com/questions/57038205/running-an-ftp-server-on-nixos
#   990 # ftps port for secure FTP with ssl/tls

#   # For custom ibackupServer.sh script
#   8090
# } -- end of ports configuration. Replace port "8090" with the evaluation of "$config__serverCommands_port" from your config.
# END SETUP ######################################################################################



set -e
#set -ex

ranWithTeeAlready="$1" # Internal use, leave empty

scriptDir="$(dirname "${BASH_SOURCE[0]}")"
tcp_fifo="$scriptDir/tcp_stream"

# Ensure perms are ok on the script
username_script=iosbackup_server
moi="$(whoami)"
if [ "$username_script" != "$moi" ]; then
    echo "Performing first-time setup"

    # Part of first-time setup (so that `iosbackup_server` can execute this script)
    sudo chown :iosbackup "${BASH_SOURCE[0]}"
    sudo chmod g+x "${BASH_SOURCE[0]}"

    # Part of first-time setup -- using ACLs (so that `iosbackup_server` can execute this script) -- this is needed since the directory perms for the script directory (`.`) are: `drwxr-xr--+ 1 yourUserNameHere iosbackup  1174 Aug 26 10:47 .` where `yourUserNameHere` is your username -- and user `iosbackup_server` is not part of the `iosbackup` group so it is part of the "other" permissions which don't have execute permissions on the directory meaning it can't run scripts within the directory. So we add execute permission for the `iosbackup_server` user using access control lists (ACLs):
    setfacl -m u:iosbackup_server:x "$scriptDir"
    # Verify for reference:
    getfacl "$scriptDir"

    # Make a fifo that will persist after this script is run, and allow this script to access it when run later as the `iosbackup_server` user:
    mkfifo "$tcp_fifo"
    setfacl -m u:iosbackup_server:rw "$tcp_fifo"
    # Verify for reference:
    getfacl "$tcp_fifo"
fi

# Script setup #
source "$scriptDir/makeSnapshot.sh" # Sets `makeSnapshot` function
source "$scriptDir/teeWithTimestamps.sh" # Sets `tee_with_timestamps` function

# Grab config
source "$scriptDir/config.sh"

dest_script="$config__drive/home/$username_script"
if [ ! -e "$dest_script" ]; then
    # Part of first-time setup
    echo "$dest_script doesn't exist, making it with sudo:"
    sudo mkdir "$dest_script"
    sudo chown "$username_script" "$dest_script"
    sudo chmod go-rwx "$dest_script"
fi

# We will be using this user, so verify we are currently that user:
#username_script=iosbackup_server
# Verify user
#moi="$(whoami)"
if [ "$username_script" != "$moi" ]; then
    #echo "Expected \"$username_script\" to equal whoami user \"${moi}\". Exiting."
    #exit 1

    echo "Finished first-time setup."
    exit
fi

#source "$scriptDir/allConfiguredFTPUsers.sh" # Puts users into `users` array

logfile="$dest_script/ibackupServer_logs/$(date '+%Y-%m-%d %I-%M-%S %p').log.txt"
logsDir="$(dirname "$logfile")"
if [ ! -e "$logsDir" ]; then
    mkdir "$logsDir"
fi

# Re-run with tee if needed
if [ -z "$ranWithTeeAlready" ]; then
    echo "[ibackupServer] Running with tee to logfile $logfile"
    bash "$0" "$logfile" 2>&1 | tee_with_timestamps "$logfile"
    exit
fi
# #


username=
username_ftp=
dest=
# Input: $1 = udid to use
# Outputs to global variables above
setVars() {
    local udid="$1"

    # Get the FTP user account for this udid
    username="$(python3 "$scriptDir/udidToFolderLookupTable.py" "$udid")"
    username_ftp="${username}_ftp" # Append `_ftp` to it to make the FTP username

    dest="$config__drive/home/$username/@iosBackups"
}

#started=0 # 1 if backup is considered currently running, 0 if not running
# Load API for wasBackedUp etc. -- we use it to indicate if a backup is currently *running* or not instead of whether it was backed up! #
source wasBackedUp.sh
# #

startBackup() {
    local udid="$1"
    # With backupMyIPhone.sh, just make a snapshot, then exit (the `1` after "$udid" does this)
    #"$scriptDir/backupMyIPhone.sh" '' 1 0 0 "$udid" 1
    # [nvm:] Now open up the samba (SMB) share for access
    # [nvm:] (Client uses: mount.smb3 command to access it from Linux)
    # [instead:] open vsftpd for access
    setVars "$udid"

    # Open vsftpd on this user account for access
    echo "[ibackupServer] Opening vsftpd for user $username_ftp with device UDID ${udid}"
    if [ ! -e "$dest" ]; then
	echo "[ibackupServer] Error: $dest doesn't exist. Not starting backup."
	#started=0
	setWasBackedUp_ "$udid" 0
    else
	backupsLocation="$dest"
	# Show the backups at {the ftp location}(<--the user's home directory)
	#mount --bind "$backupsLocation" "/home/$username_ftp"
	# https://unix.stackexchange.com/questions/115377/mount-bind-other-user-as-myself -- bindfs ( https://bindfs.org/ ) allows you to change users albeit a bit slower than Linux kernel bind mounts(<--`mount --bind`):
	# This is so useful: https://bindfs.org/docs/bindfs.1.html : "--map" : "Given a mapping user1/user2, all files owned by user1 are shown as owned by user2. When user2 creates files, they are chowned to user1 in the underlying directory. When files are chowned to user2, they are chowned to user1 in the underlying directory. Works similarly for groups."
	sudo bindfs --map="$username"/"$username_ftp" "$backupsLocation" "/home/$username_ftp" # (`sudo` is used; this requires a sudoers entry -- see README.md under the `## Server-client mode` section for more info)
	#started=1
	setWasBackedUp_ "$udid" 1
	echo "[ibackupServer] Started vsftpd for user $username_ftp with device UDID ${udid}."
    fi
}

finishBackup() {
    local udid="$1"
    local unsuccessful="$2"

    # Check some preconditions
    if [ "$started" != "1" ]; then
	local uns=
	if [ "$unsuccessful" == 1 ]; then
	    uns="Unsuccessful"
	fi
	echo "[ibackupServer] Backup is not currently started; can't finishBackup${uns}. Ignoring this command."
	return
    fi

    setVars "$udid"

    if [ "$unsuccessful" != "1" ]; then
	# Make a snapshot
	btrfsDaemonPort="$config__btrbk_daemon_port"
	makeSnapshot "$(dirname "$dest")"
    fi

    # Remove bindfs mount
    sudo umount "/home/$username_ftp" # (`sudo` is used; this requires a sudoers entry -- see README.md under the `## Server-client mode` section for more info)

    # Backup is finished
    #started=0
    setWasBackedUp_ "$udid" 0
    echo "[ibackupServer] Stopped vsftpd for user $username_ftp with device UDID ${udid}."
}

runCommand() {
    echo "[ibackupServer] runCommand: $@"
    local command="$@"
    local arg0="$(echo "$command" | awk '{ print $1 }')"
    local arg1="$(echo "$command" | awk '{ print $2 }')"

    local udid="$arg1"
    source wasBackedUp.sh
    local started=$(wasBackedUp_ "$udid")

    if [ "$arg0" == "startBackup" ] && [ "$started" == "0" ]; then
	startBackup "$arg1"
    elif [ "$arg0" == "startBackup" ] && [ "$started" == "1" ]; then
        echo "[ibackupServer] Backup is already \"started\", nothing to do. It must have been left on or something..."
    elif [ "$arg0" == "finishBackup" ]; then
	finishBackup "$arg1"
    elif [ "$arg0" == "finishBackupUnsuccessful" ]; then
	finishBackup "$arg1" 1
    else
	echo "[ibackupServer] Unknown command: $command"
    fi
}

commandProcessor() {
    local stream="$1"
    export -f runCommand
    export -f startBackup
    export -f finishBackup
    export -f makeSnapshot
    #export started
    export config__btrbk_daemon_port
    export -f setVars
    export config__drive
    export scriptDir
    function processOutput() {
	while read data; do
	    echo "${data}"

	    local regex=$(
cat <<'END_HEREDOC'
^\[ibackupServer\] Started vsftpd for user ([^ ]+) with device UDID (.*).$
END_HEREDOC
)
	    #if [[ "$data" == "[ibackupServer] Started vsftpd for user "* ]]; then
	    if [[ $data =~ $regex ]]; then
		# Started successfully -- update this global variable since the subprocess can't update globals
		local user="${BASH_REMATCH[1]}"
		local udid="${BASH_REMATCH[2]}"
		#started=1
		setWasBackedUp_ "$udid" 1
		echo "[ibackupServer] Command processor recorded start for UDID $udid"
	    else
		local regex=$(
cat <<'END_HEREDOC'
^\[ibackupServer\] Stopped vsftpd for user ([^ ]+) with device UDID (.*).$
END_HEREDOC
)
		if [[ $data =~ $regex ]]; then
		    # Stopped successfully -- update this global variable since the subprocess can't update globals
		    local user="${BASH_REMATCH[1]}"
		    local udid="${BASH_REMATCH[2]}"
		    #started=0
		    setWasBackedUp_ "$udid" 0
		    echo "[ibackupServer] Command processor recorded stop for UDID $udid"
		fi
	    fi
	done
    }
    cat < "$stream" | xargs -d\\n -n1 bash -c 'runCommand $1' bash | processOutput
}

# Wait for a connection to take a snapshot
#mkfifo "$tcp_fifo"
# Read from the pipe first, in the background
commandProcessor "$tcp_fifo" &
# Write to the pipe in the foreground
# `-k` "to stay listening for another connection after its current connection is completed." ( https://unix.stackexchange.com/questions/423407/how-can-i-keep-netcat-connection-open )
#nc -v -l -p "$config__serverCommands_port" > "$tcp_fifo"
nc -v -d -k -l 0.0.0.0 "$config__serverCommands_port" > "$tcp_fifo" # 0.0.0.0 lets any computer connect ( https://poe.com/Assistant )
NC_PID="$!" # get the process ID of the netcat process spawned above
