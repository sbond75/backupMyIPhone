# backupMyIPhone

## Demo

1. Initialize:
   1. `sudo groupadd iosbackup` to make the `iosbackup` group
   2. `sudo useradd UserNameHere` to create user `UserNameHere` (replace this with a new  user name to make backups under). Make as many users as desired.
   3. `sudo usermod -a -G iosbackup UserNameHere` to add `UserNameHere` to the `iosbackup` group. Do this for all the users added in the previous step.
   4. `sudo ./backupMyIPhone.sh '' 1 0 1 'YourDeviceUDIDHere'`
2. Run a backup "daemon": `sudo su YourBackupUserHere -c "./backupMyIPhone.sh '' 1 0 1 'YourDeviceUDIDHere'"` where `YourBackupUserHere` is in the `iosbackup` group.
