# backupMyIPhone

## Demo

1. Initialize:
   1. `sudo groupadd iosbackup` to make the `iosbackup` group
   2. `sudo useradd UserNameHere` to create user `UserNameHere` (replace this with a new user name to make backups under). Make as many users as desired.
   3. `sudo usermod -a -G iosbackup UserNameHere` to add `UserNameHere` to the `iosbackup` group. Do this for all the users added in the previous step.
   4. `sudo ./ibackup.sh '' 1 0 8089 UserNameHere` to perform first-time setup
2. Add your device UDID to `udidToFolderLookupTable.py`
3. `sudo -E su --preserve-environment UserNameHere` and then run one of these in this shell to make a backup:
   1. To backup as a daemon running now, which will additionally run at 12:01 AM *or* 24 hours from now, whichever is closest, repeatedly:
	  - `./ibackup.sh YourDeviceUDIDHere 0 0 8089 UserNameHere` where the `YourDeviceUDIDHere` is the device UDID from the output of the first-time setup above.
   2. Run these as sudo the first time (as any user), then run them in the shell created above afterwards if needed:
	  1. To backup immediately once -- *not* dry run:
		  - `sudo ./backupMyIPhone.sh '' 1 0 0 'YourDeviceUDIDHere'`
	  2. Or: to backup immediately once -- dry run:
		  - `sudo ./backupMyIPhone.sh '' 1 0 1 'YourDeviceUDIDHere'`






Nvm:
2. Run a backup "daemon": `sudo su YourBackupUserHere -c "./backupMyIPhone.sh '' 1 0 1 'YourDeviceUDIDHere'"` where `YourBackupUserHere` is in the `iosbackup` group.
