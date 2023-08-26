# backupMyIPhone

A tool to take control of backing up your iOS device to your own server via Wi-Fi or USB.

## Demo

1. Run this to start the avahi daemon: `systemctl start avahi-daemon.service` # TODO: install how to
1. Initialize:
   1. Add a destination backup drive to a new file in the repo root, `config.sh`, by basing the file off a copy of the one in `template` folder made with: `cp template/config.sh ./` and then editing the copy. You should enter in something like `/mnt/yourDriveMountPointHere/home`, where the `/mnt/yourDriveMountPointHere` part can be anything as long as it is a valid mountpoint (`mountpoint /mnt/yourDriveMountPointHere`should return an exit code of 0).
   2. In the destination backup drive mentioned above, make a new folder called `home`.
   1. `sudo groupadd iosbackup` to make the `iosbackup` group
   2. Make a user just for usbmuxd in the `iosbackup` group:
	  1. `sudo useradd iosbackup_usbmuxd`
	  2. `sudo usermod -a -G iosbackup iosbackup_usbmuxd`
	  3. Give the users in the `iosbackup` group permission to run `usbmuxd` under the account created above by editing `/etc/sudoers` if you're not on NixOS, or by adding `security.sudo.configFile = '' Config strings go here ''` to your NixOS config at `/etc/nixos/configuration.nix` if you are on NixOS, to add the following line: `%iosbackup ALL=(iosbackup_usbmuxd)NOPASSWD:ALL USBMUXD_FILEPATH` where `USBMUXD_FILEPATH` is something like `/nix/store/zsmdrh44nl59v6db340j7w81cg77ys8v-usbmuxd2-753b79eaf317c56df6c8b1fb6da5847cc54a0bb0/bin/usbmuxd` which you get from doing `which usbmuxd` when in the `nix-shell` present in this repo root. This limits the group `iosbackup` to, when running sudo, only be able to run the `usbmuxd` command as the user `iosbackup_usbmuxd`.
	  4. If on NixOS, reload your config using `sudo nixos-rebuild switch` to apply the sudoers change above.
   3. `sudo useradd UserNameHere` to create user `UserNameHere` (replace this with a new user name to make backups under). Make as many users as desired.
   4. `sudo usermod -a -G iosbackup UserNameHere` to add `UserNameHere` to the `iosbackup` group. Do this for all the users added in the previous step.
   5. First-time setup
	  1. Plug the device in to the computer via USB
	  1. `sudo ./backupMyIPhone.sh '' 1 1 0`, note the UDID from the output
	  2. Enter passcode and "Trust this computer" on the device
	  2. Add your device UDID (shows in the output from the above `./backupMyIPhone.sh` command) to a new file in the repo root, `udidToFolderLookupTable.py`, by basing the file off a copy of the one in `template` folder made with: `cp template/udidToFolderLookupTable.py ./` and then editing the copy.
	  3. `sudo ./backupMyIPhone.sh '' 1 1 0 YourDeviceUDIDHere` (where `YourDeviceUDIDHere` is the UDID you saw) to perform first-time setup. This requires the device to be connected via USB.
	  4. `sudo pkill usbmuxd` at the end.
2. `sudo -E su --preserve-environment UserNameHere` (where `UserNameHere` is a user created above) and then run one of the following in this shell to make a backup. The following commands don't require the device to be connected to the computer via USB, only to be plugged in and charging somewhere on the same local WiFi network.
   1. Run these as sudo the first time (as any user), then run them in the shell created above afterwards if needed:
	  1. To backup immediately once if it can connect and also repeating every day -- *not* dry run:
		  - `./backupMyIPhone.sh '' 1 0 0 'YourDeviceUDIDHere'`
	  2. Or: to backup immediately once if it can connect and also repeating every day -- dry run:
		  - `./backupMyIPhone.sh '' 1 0 1 'YourDeviceUDIDHere'`
	  3. Or: to backup via USB instead (it will start usbmuxd as root with sudo):
		  - Run without the `sudo -E su --preserve-environment UserNameHere` shell mentioned above: `./backupMyIPhone.sh "" 1 0 0 'YourDeviceUDIDHere' 0 1 ./shell_new_libimobiledevice.nix` (last argument is optional; it provides a Nix shell that has a newer libusbmuxd version of your choice)
3. Run `./ibackup.sh` (with additional arguments like the above) for as many users as needed to make the backup daemons for each user. (They should all end up sharing the same usbmuxd instance.)

## Server-client mode

Besides using one computer connected to an iOS device to perform a backup, there is another way to run these backup tools. This method uses a "client" computer which connects to a "server" computer. The iOS device is connected to the "client", and the client performs the backup but transfers the backed-up files to the server via FTP (vsftpd). To use this mode, perform the following steps:

1. Make a user just for the backup server in the `iosbackup` group:
   1. `sudo useradd iosbackup_server`
   2. `sudo usermod -a -G iosbackup iosbackup_server`
2. Perform the steps inside the comments of `ibackupClient.sh` on the client computer (tested on Raspberry Pi)
3. Perform the steps inside the comments of `ibackupServer.sh` on the server computer (tested on NixOS)
4. In a similar method to the description of `/etc/sudoers` under the [Demo](##Demo) section above, add a line like the below (evaluate the code block below with bash first to process the echo commands, then put the output into sudoers) to your system's sudoers for each FTP user added to `config.sh` (users ending in `_ftp`; see `template/config.sh` for more info on the `config.sh` file if needed):
```
username=userNameHere # Put your username here (without `_ftp`)

makeEntry() {
    local username="$1"
    source config.sh
    backupsLocation="$config__drive/home/$username/@iosBackups"

    # WARNING: if `backupsLocation` or `username` contain spaces, it may cause a security issue; see https://unix.stackexchange.com/questions/279125/allow-user-to-run-a-command-with-arguments-which-contains-spaces/279142#279142
    echo "iosbackup_server ALL=(root)NOPASSWD: /nix/store/z4ywgk1yma7cnswrrcqqbh0z33lag35f-bindfs-1.15.1/bin/bindfs" --map="$username"/"${username}_ftp" "$backupsLocation" "/home/${username}_ftp"
	echo "iosbackup_server ALL=(root)NOPASSWD: /nix/store/h48w2b4vj544w45ihzdv8h5djz2d95di-umount-util-linux-2.36.2/bin/umount" "/home/${username}_ftp"
}

makeEntry "$username"
```

5. Setup the server further by running this: `./ibackupServer.sh` (run as any user with `sudo` permissions since `sudo` will be used within the script).
6. Run this command on the server to start the backup server: `sudo -E su --preserve-environment iosbackup_server ./ibackupServer.sh`
7. Run this command on the client to start listening for iOS devices to be plugged into usbmuxd on the client via USB: `./ibackupClient.sh` (you will be prompted for sudo to run usbmuxd with)

## Tools

- Debug how usb/WiFi connections are doing: `nix-shell`, then `sudo usbmuxd -vv --debug --debug`



Nvm:
1. Internal: `sudo ./ibackup.sh '' 1 0 8089 UserNameHere` to perform first-time setup. This requires the device to be connected via USB.
2. Internal: to backup as a daemon running now, which will additionally run at 12:01 AM *or* 24 hours from now, whichever is closest, repeatedly:
   - `./ibackup.sh YourDeviceUDIDHere 0 0 8089 UserNameHere` where `YourDeviceUDIDHere` is the device UDID from the output of the first-time setup above, and `UserNameHere` is a user created above.
2. Run a backup "daemon": `sudo su YourBackupUserHere -c "./backupMyIPhone.sh '' 1 0 1 'YourDeviceUDIDHere'"` where `YourBackupUserHere` is in the `iosbackup` group.
