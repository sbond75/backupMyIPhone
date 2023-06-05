# Script expects these variables to be set:
# noStart
# dest_usbmuxd
# tee_with_timestamps
# nixShellToUseForUSB

if [ "$noStart" == "0" ]; then # NOTE: this may start up anyway despite there not being any other users... and that is ok, it will just have permission denied since one user owns the logfile at a time (the one who spawned it, currently)..
    logfile_usbmuxd="$dest_usbmuxd/logs/$(date '+%Y-%m-%d %I-%M-%S %p').log.txt"
    echo "[ibackup] Starting network daemon with logfile ${logfile_usbmuxd}..."
    
    # (Run original `sudo` command, not wrapped sudo function in bash near the top of this script:)
    # Nohup so it runs as a "daemon":
    sudo_="$(PATH="/run/wrappers/bin/:$PATH" which sudo)"
    export -f tee_with_timestamps # export the function to make it available in the child process ( https://unix.stackexchange.com/questions/22796/can-i-export-functions-in-bash )
    if [ "$useUSB" == "1" ]; then
	#nousb="--nowifi"
	nousb=
	user= # (root)
	cmd2="bash"
	# Note: printf %q will quote any special characters in there, in case $username has spaces or other special characters:
	# `declare -f` to put the contents of the function in (paste it) basically -- https://unix.stackexchange.com/questions/269078/executing-a-bash-script-function-with-sudo :
	scriptDir="$(dirname "${BASH_SOURCE[0]}")"
	maybeSudo="{ $(declare -f tee_with_timestamps) ; export -f tee_with_timestamps; typeset -fx tee_with_timestamps; sudo -E su --preserve-environment $(printf '%q' "$username") -- '$(printf '%q' "$scriptDir")/bashHack.sh' -c 'tee_with_timestamps \""'$1'"\"' \""'$0'"\" \""'$2'"\"" # Need sudo perms for tee to write into `/mnt/ironwolf/home/iosbackup_usbmuxd/logs/` as $username
	maybeSudoEnd=" ; }"
    else
	nousb="--nousb"
	user="-u iosbackup_usbmuxd"
	cmd2="nohup bash"
	maybeSudo='tee_with_timestamps "$2"'
	maybeSudoEnd=
    fi

    if [ "$quietUsbmuxd" == 1 ]; then
	extrasVerbose1=''
	extrasVerbose2=''
    else
	extrasVerbose1='-vv'
	extrasVerbose2='--debug'
    fi

    if [ "$useUSB" == "1" ]; then
	#sudo bash -c 'usbmuxd -vv '"$nousb"' --debug 2>&1 | tee_with_timestamps "$2"' bash "" "$logfile_usbmuxd" # https://stackoverflow.com/questions/26109878/running-a-program-in-the-background-as-sudo
	#(bash -c '"$1" '"$user"' usbmuxd -vv '"$nousb"' --debug 2>&1 | '"$maybeSudo"' '"$maybeSudoEnd" bash "$sudo_" "$logfile_usbmuxd" &) &
	(bash -c '"$1" '"$user"' bash '"$(printf '%q' "$scriptDir/runWithNixBash.sh")"' '"$(printf '%q' "$nixShellToUseForUSB")"' usbmuxd '"$extrasVerbose1"' --foreground '"$nousb"' 2>&1 | '"$maybeSudo"' '"$maybeSudoEnd" bash "$sudo_" "$logfile_usbmuxd" &) &
    else
	(nohup bash -c '"$1" '"$user"' usbmuxd '"$extrasVerbose1"' '"$nousb"' '"extrasVerbose2"' 2>&1 | '"$maybeSudo"' '"$maybeSudoEnd" bash "$sudo_" "$logfile_usbmuxd" &) & # https://stackoverflow.com/questions/3430330/best-way-to-make-a-shell-script-daemon
    fi
    
    #runuser -u iosbackup_usbmuxd -- usbmuxd -vv --nousb --debug 2>&1 | tee_with_timestamps "$logfile_usbmuxd" &
fi
