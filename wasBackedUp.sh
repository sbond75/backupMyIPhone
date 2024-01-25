# Make an array for all the devices' backup statuses (whether they were backed up today or not) per UDID
wasBackedUp=()
wasBackedUp_timesFinished=() # time strings for last backup finished time, or "" for no backup at all yet
# Nvm: this is for users, not UDIDs: #
# source "$scriptDir/allConfiguredFTPUsers.sh" # Puts users into `users` array
# for i in "${users[@]}"
# do
#     wasBackedUp+=(0) # 0 for false
# done

# function wasBackedUp_() {
#     local usernameWithFTPSuffix="$1"
#     local index = 0
#     for i in "${users[@]}"
#     do
# 	if [ "$i" == "$usernameWithFTPSuffix" ]; then
# 	    # Found it
# 	    echo "${wasBackedUp[index]}"
# 	    return
# 	fi
# 	let index=${index}+1 # (`let` is for arithmetic -- https://stackoverflow.com/questions/6723426/looping-over-arrays-printing-both-index-and-value , https://stackoverflow.com/questions/18704857/bash-let-statement-vs-assignment )
#     done
#     # If we get here, it wasn't found... return "2" instead
#     echo 2
# }

# function setWasBackedUp_() {
#     local usernameWithFTPSuffix="$1"
#     local setTo="$2"
#     local index = 0
#     for i in "${users[@]}"
#     do
# 	if [ "$i" == "$usernameWithFTPSuffix" ]; then
# 	    # Found it
# 	    wasBackedUp[index]="$setTo"
# 	    echo 1 # success
# 	    return
# 	fi
# 	let index=${index}+1 # (`let` is for arithmetic -- https://stackoverflow.com/questions/6723426/looping-over-arrays-printing-both-index-and-value , https://stackoverflow.com/questions/18704857/bash-let-statement-vs-assignment )
#     done
#     # If we get here, it wasn't found... return "2" instead
#     echo 2
# }
# End nvm #
# Actual stuff: #
udidTableKeys=$(python3 "$scriptDir/udidToFolderLookupTable.py" "" 0 1)
readarray -t udidTableKeysArray <<< "$udidTableKeys" # This reads {a newline-delimited array of strings} out of a string and into an array. `-t` to strip newlines. ( https://www.javatpoint.com/bash-split-string#:~:text=In%20bash%2C%20a%20string%20can,the%20string%20in%20split%20form. , https://stackoverflow.com/questions/41721847/readarray-t-option-in-bash-default-behavior )

for i in "${udidTableKeysArray[@]}"
do
    wasBackedUp+=(0) # 0 for false, "s" for started, "f" for finished
    wasBackedUp_timesFinished+=("") # "" for "null" time
done

# Outputs #
wasBackedUp__timeTillNextBackup=
# #
function wasBackedUp_() {
    local udid="$1"
    local index=0
    for i in "${udidTableKeysArray[@]}"
    do
	if [ "$i" == "$udid" ]; then
	    # Found it
	    res="${wasBackedUp[index]}"
	    if [ "$res" == "s" ] || [ "$res" == "f" ]; then
		# Check if this is too old
		local now=
		if [ -z "$2" ]; then
		    now="$(date +%s)" # Get time in seconds since UNIX epoch ( https://stackoverflow.com/questions/1092631/get-current-time-in-seconds-since-the-epoch-on-linux-bash )
		else
		    now="$2"
		fi
		local past="${wasBackedUp_timesFinished[index]}"
		if [ "$past" == "" ]; then
		    # Null time; consider this as original status
		    wasBackedUp__timeTillNextBackup=2147483647 # backup could be in-progress, so time until next backup is indeterminate (only when the backup is finished do we say the next backup can happen after `inc` time below)
		    echo "$res"
		fi
		local inc=$((86400 / 2)) # Seconds in a day divided by 2
		local next=$(($past + $inc))
		wasBackedUp__timeTillNextBackup=$(($next - $now))
		if [ "$now" -ge "$next" ]; then
		    echo "0" # always make this "too old" of a backup, so we report "0" to mean "not backed up"
		else
		    echo "$res" # keep original status
		fi
	    else
		wasBackedUp__timeTillNextBackup=0
		# "Return" it
		echo "$res"
	    fi
	    return
	fi
	let index=${index}+1 # (`let` is for arithmetic -- https://stackoverflow.com/questions/6723426/looping-over-arrays-printing-both-index-and-value , https://stackoverflow.com/questions/18704857/bash-let-statement-vs-assignment )
    done
    # If we get here, it wasn't found... return "2" instead
    echo 2
}

function setWasBackedUp_() {
    local udid="$1"
    local setTo="$2"
    local index=0
    for i in "${udidTableKeysArray[@]}"
    do
	if [ "$i" == "$udid" ]; then
	    # Found it
	    wasBackedUp[index]="$setTo"

	    local now=
	    if [ -z "$3" ]; then
		now="$(date +%s)" # Get time in seconds since UNIX epoch ( https://stackoverflow.com/questions/1092631/get-current-time-in-seconds-since-the-epoch-on-linux-bash )
	    else
		now="$3"
	    fi
	    
	    if [ "$setTo" == "f" ]; then
		wasBackedUp_timesFinished[index]="$now"
	    else
		wasBackedUp_timesFinished[index]=""
	    fi

	    echo 1 # success
	    return
	fi
	let index=${index}+1 # (`let` is for arithmetic -- https://stackoverflow.com/questions/6723426/looping-over-arrays-printing-both-index-and-value , https://stackoverflow.com/questions/18704857/bash-let-statement-vs-assignment )
    done
    # If we get here, it wasn't found... return "2" instead
    echo 2
}
# #
