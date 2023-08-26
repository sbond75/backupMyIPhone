# Parameters:
# argument 1: folder containing @iosBackups folder
#
# Global variables required:
# ranWithTeeAlready = the logfile name in use already
# btrfsDaemonPort = the port to use to contact btrbk_daemon.py
# username = the username to save the snapshot under
# config.sh must have been sourced
makeSnapshot()
{
    local dest="$1"
    
	# Make snapshot
	if [ ! -e "$dest/@iosBackups" ]; then
		# # Make subvolume
		# echo "[ibackup] Creating Btrfs subvolume at $dest/@iosBackups"
		# cmd='btrfs subvolume create '"$dest/@iosBackups"
		# if [ "$dryRun" == "1" ]; then
		#     echo $cmd
		# else
		#     $cmd
		# fi

		echo "[ibackup] Fatal error: $dest/@iosBackups doesn't exist. It should have been created in firstTime setup earlier. Exiting."
		exit 1
	else
	    if [ -z "$(ls -A $dest/@iosBackups)" ]; then # https://superuser.com/questions/352289/bash-scripting-test-for-empty-directory
		echo "Empty $dest/@iosBackups folder, not snapshotting"
	    else
		# Make snapshot first (to save old backup status before an incremental backup which updates the old contents in-place). Only happens if onchange (if it changed -- https://manpages.debian.org/testing/btrbk/btrbk.conf.5.en.html ) #
		scriptDir="$(dirname "${BASH_SOURCE[0]}")"
		echo "[ibackup] btrbk Btrfs snapshot starting:"
		mountpoint "$config__drive" || { echo "Error: backup destination drive not mounted. Exiting."; exit 1; }
		if [ "$dryRun" == "1" ]; then
		    run=dryrun
		    #run=run
		else
		    run=run
		fi
		filename=$(basename -- "$ranWithTeeAlready")
		extension="${filename##*.}"
		filename="${filename%.*}" # Without the extension ( https://stackoverflow.com/questions/965053/extract-filename-and-extension-in-bash )
		logfileBtrbk="$(dirname "$ranWithTeeAlready")/${filename}_btrbk_ibackup.txt"
		config=$(cat << EOF
transaction_log            $logfileBtrbk
stream_buffer              512m
snapshot_dir               home/$username/_btrbk_snap
incremental                 yes
snapshot_preserve_min      7d
snapshot_preserve          14d
target_preserve_min        all
target_preserve            no
snapshot_preserve       14d
volume $config__drive
  snapshot_create  onchange
  subvolume home/$username/@iosBackups
EOF
)
		echo "$config"
		#btrbk --config=<(echo "$config") --verbose --preserve --preserve-backups --preserve-snapshots $run #run #dryrun             #"--preserve": "preserve all (do not delete anything)"                 # --loglevel=debug
		echo "$config" | python3 "$scriptDir/btrbk_run.py" "$btrfsDaemonPort" # NOTE: doesn't use the nix shell shebang due to a minor issue with `sudo -E su --preserve-environment` followed by a username to run as, which is: `error: creating directory '/run/user/1000/nix-shell-600411-0': Permission denied`. Just using the python3 we have already fixes this issue.
		exitCode="$?"
		if [ "$exitCode" != "0" ]; then
		    echo "btrbk_run.py failed with exit code $exitCode"
		    exit
		fi
		#misc cool stuff: `sudo btrbk --config="$configLocation" diff` could be nice to find where a file was changed!
		echo "[ibackup] btrbk snapshot finished."
	    fi
	fi
}
