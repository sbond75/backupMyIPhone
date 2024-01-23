# Grab config
source "$scriptDir/config.sh"

function serverCmd_impl() {
    local command="$1"
    local udid="$2"

    # `-v` for verbose (to show why connections fail, if they do)
    # `-N` to exit after sending ( https://unix.stackexchange.com/questions/332163/netcat-send-text-to-echo-service-read-reply-then-exit )
    netcat -N -v "$config__host" "$config__serverCommands_port" <<< "$command $udid" # (`<<<` is called a "here string" ( https://askubuntu.com/questions/443227/sending-a-simple-tcp-message-using-netcat , https://stackoverflow.com/questions/16045139/redirector-in-ubuntu )
}

function serverCmd() {
    local retryTillSuccess="$2"
    local udid="$3"

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
	serverCmd_impl "$1" "$udid"
    fi
}

function urlencode() {
    # https://askubuntu.com/questions/53770/how-can-i-encode-and-decode-percent-encoded-strings-on-the-command-line , https://stackoverflow.com/questions/40557606/how-to-url-encode-in-python-3
    python3 -c "import urllib.parse; import sys; print(urllib.parse.quote(  sys.argv[1] if len(sys.argv) > 1 else sys.stdin.read()[0:-1], safe=''))" "$1"
}

# Load API for wasBackedUp etc. #
source wasBackedUp.sh
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
