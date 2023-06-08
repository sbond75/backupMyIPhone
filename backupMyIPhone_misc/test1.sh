set -e

# Based on https://stackoverflow.com/questions/39239379/add-timestamp-to-teed-output-but-not-original-output
# Usage: `echo "test" | tee_with_timestamps "file.txt"`
function tee_with_timestamps () {
    #read -u 3 tempNvm # Read "temp" message
    #read -u 3 theJob # Reads from file descriptor 3 into variable $theJob ( https://bash.cyberciti.biz/guide/Reads_from_the_file_descriptor_(fd) )
    set +e
    theJob="$(pgrep usbmuxd)"
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
	fi
    done
}

#bash -c 'sleep 1; echo hi' | tee_with_timestamps &
nix-shell --run 'echo hi' 2>&1 | tee_with_timestamps &
sleep 3
