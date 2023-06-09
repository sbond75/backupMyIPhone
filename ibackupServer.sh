#! /usr/bin/env nix-shell
#! nix-shell -i bash -p netcat-gnu samba

startBackup() {
    local udid="$1"
    # With backupMyIPhone.sh, just make a snapshot, then exit (the `1` after "$udid" does this)
    ./backupMyIPhone.sh '' 1 0 0 "$udid" 1
    # Now open up the samba (SMB) share for access
    # (Client uses: mount.smb3 command to access it from Linux)
}

finishBackup() {
    local udid="$1"
    # Just make a snapshot, then exit (the `1` after "$udid" does this)
    ./backupMyIPhone.sh '' 1 0 0 "$udid" 1
}

runCommand() {
    local command="$1"
    local arg0="$(echo "$command" | awk '{ print $1 }')"
    local arg1="$(echo "$command" | awk '{ print $2 }')"
    if [ arg0 == "startBackup" ]; then
	startBackup "$arg1"
    elif [ arg0 == "finishBackup" ]; then
	finishBackup "$arg1"
    fi
}

commandProcessor() {
    local stream="$1"
    export -f runCommand
    export -f startBackup
    cat < "$stream" | xargs -d\\n -n1 bash -c runCommand bash
}

# Wait for a connection to take a snapshot
mkfifo tcp_stream
# Read from the pipe first, in the background
commandProcessor tcp_stream &
# Write to the pipe in the foreground
nc -l -p 8090 > tcp_stream
NC_PID="$!" # get the process ID of the netcat process spawned above
