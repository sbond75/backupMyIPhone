#! /usr/bin/env bash

if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as root. Exiting."
    exit 1
fi

set -e

# Based on https://stackoverflow.com/questions/39239379/add-timestamp-to-teed-output-but-not-original-output
# Usage: `echo "test" | tee_with_timestamps "file.txt"`
function tee_with_timestamps () {
    #read -u 3 tempNvm # Read "temp" message
    #read -u 3 theJob # Reads from file descriptor 3 into variable $theJob ( https://bash.cyberciti.biz/guide/Reads_from_the_file_descriptor_(fd) )
    set +e
    exitCode=1
    while [ "$exitCode" != "0" ]; do
	theJob="$(pgrep usbmuxd)"
	exitCode="$?"
	sleep 1
    done
    set -e
    
    reachedCleanup=0
    while read data; do
	#while [ -z "$theJob" ]; do sleep 1; done # Wait for this variable to be populated (should happen very quickly)
	#while { ! true >&3; } 2> /dev/null ; do sleep 1; done # Wait for file descriptor 3 to exist ( https://unix.stackexchange.com/questions/206786/testing-if-a-file-descriptor-is-valid )

	echo "${data}"

	#if [[ "${data}" == *"idevice_connect()"* ]] && [ "$reachedCleanup" == 0 ]; then
	if [[ "${data}" == *"chown for lockfile:"* ]] && [ "$reachedCleanup" == 0 ]; then
	    reachedCleanup=1
	#elif [[ "${data}" == *"done!"* ]] && [ "$reachedCleanup" == "1" ]; then
	#    reachedCleanup=2
	    # Terminate the usbmuxd process after 1 second
	    echo "Sending SIGINT to root usbmuxd with pid $theJob"
	    { sleep 1; kill -SIGINT "$theJob"; } &  # Based on https://stackoverflow.com/questions/1624691/linux-kill-background-task
	fi
    done
}

# Fire up usbmuxd as root once just to get the perms set up, then terminate it after the "chown for lockfile" message prints.
set +e
pgrep usbmuxd
exitCode="$?"
set -e
if [ "$exitCode" != "1" ]; then # usbmuxd is running or something else is wrong
    echo "pgrep returned exit code ${exitCode} -- usbmuxd may be running already. Exiting."
    exit 1
fi
#exec 3> >(
    nix-shell --run 'usbmuxd -vv --nousb --debug --debug' 2>&1 | tee_with_timestamps &
#) # Open up file descriptor 3
#theJob="$(jobs -p 1)"
#theJob="$(pgrep usbmuxd)"
#echo "$theJob" >&3 # Writes the pid to file descriptor 3

# Now fire up btrbk_daemon
dryRun=""
port=8089

# Run btrbk "daemon", as root so btrfs snapshots work
echo "Starting btrbk daemon..."
./btrbk_daemon.py "" "" "$dryRun" "$port" # NOTE: this script may fail if port 8089 is in use. We will assume it is an exiting btrbk daemon that is causing that failure...
# TIP: To get error logs from the daemon: `find /mnt/ironwolf/home/iosbackup_usbmuxd/logs/ -name '*.log_btrbk_daemon.txt' -print0 | xargs -r -0 ls -1 -t | head -1` (finds the last modified file based on https://stackoverflow.com/questions/5885934/bash-function-to-find-newest-file-matching-pattern )
