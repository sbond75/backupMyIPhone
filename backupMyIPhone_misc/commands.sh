#! /usr/bin/env nix-shell
#! nix-shell -p bash python3 -i bash

usage()
{
    echo "Usage: $0"' <vls|vlu|vl|h|help|p|q|quit> [user] [extras]

<vls>: View Latest concise backup Status logs
<vlu>: View Latest Usbmuxd logs
<vl>: View Latest logs of User with name [user] followed by `_iosbackup`. You can use partial names; they will be auto-completed using udidToFolderLookupTable.py.

For the above commands, [extras] can optionally be used to select the nth newest file instead of the first one (default).

<h|help>: print this Help message
<p>: enter rePl for asking for the above commands.
<q|quit>: Quit the repl'
}

if [ -z "$1" ]; then
    usage
    exit 1
fi

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd ) # https://stackoverflow.com/questions/59895/how-do-i-get-the-directory-where-a-bash-script-is-located-from-within-the-script

cmd="$1"
user="$2"
extras_="$3"

viewLatestFileWithPattern()
{
    viewLatestFileWithPattern.sh "$@" -- -n +F -S
}

repl()
{
    local isREPL="$1"
    local firstRun=1

    while [ "$isREPL" == "1" ] || [ "$firstRun" == "1" ]; do
	if [ "$isREPL" == "1" ]; then
	    # Read in command
	    # https://phoenixnap.com/kb/bash-read#:~:text=Bash%20read%20Syntax,-The%20syntax%20for&text=The%20read%20command%20takes%20the,the%20argument%20names%20is%20optional. , https://stackoverflow.com/questions/45697432/how-to-allow-arrow-keys-in-read-command
	    read -e -p "Enter command: " cmd user extras_
	fi

	local gotoEnd=0
	local error=0
	local extras="$extras_"
	if [ -z "$extras" ]; then
	    extras=()
	else
	    extras=("$extras_")
	fi
	if [ "$cmd" == "vls" ]; then
	    if [ -z "$user" ]; then # (`-z` is true for empty arrays (i.e. `()`) too)
		user="iosbackup"
	    else
	       # Auto-complete user
	       user="$(python3 "$SCRIPT_DIR/autocompleteUser.py" "$user")"
	       if [ "$?" != "0" ]; then
		   echo "$user"
		   gotoEnd=1
	       fi
	    fi
	elif [ "$cmd" == "vl" ]; then
	    if [ -z "$user" ]; then
		echo "Error: must provide a user."
		gotoEnd=1
		error=1
	    else
	       # Auto-complete user
	       user="$(python3 "$SCRIPT_DIR/autocompleteUser.py" "$user")"
	       if [ "$?" != "0" ]; then
		   echo "$user"
		   gotoEnd=1
	       fi
	    fi
	else
	    extras=("$user")
	fi

	if [ "$gotoEnd" == "0" ]; then
	    if [ "$cmd" == "vls" ]; then
		# echo "$extras"
		# exit
		viewLatestFileWithPattern '/mnt/ironwolf/home/iosbackup_usbmuxd/logs/*_'"$user" "${extras[@]}"
	    elif [ "$cmd" == "vlu" ]; then
		viewLatestFileWithPattern '/mnt/ironwolf/home/iosbackup_usbmuxd/logs/*txt' "${extras[@]}"
	    elif [ "$cmd" == "vl" ]; then
		viewLatestFileWithPattern '/mnt/ironwolf/home/'"$user"'/logs/*txt' "${extras[@]}"
	    elif [ "$cmd" == "h" ] || [ "$cmd" == "help" ]; then
		usage
	    elif [ "$cmd" == "p" ]; then
		# Enter REPL
		if [ "$isREPL" == "1" ]; then
		    echo "Already in REPL."
		else
		    repl "1"
		fi
	    elif [ "$cmd" == "q" ] || [ "$cmd" == "quit" ]; then
		exit 0
	    else
		echo "Error: unrecognized command $cmd."
		error=1
	    fi
	fi

	if [ "$error" == "1" ]; then
	    if [ "$isREPL" != "1" ]; then
		exit 1
	    fi
	fi
	firstRun=0
	echo
    done
}

repl 0
