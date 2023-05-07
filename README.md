# backupMyIPhone

## Demo

1. Run this to start the avahi daemon: `systemctl start avahi-daemon.service` # TODO: install how to
1. Initialize:
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
	  2. Add your device UDID (shows in the output from the above `./backupMyIPhone.sh` command) to `udidToFolderLookupTable.py`
	  3. `sudo ./backupMyIPhone.sh '' 1 1 0 YourDeviceUDIDHere` (where `YourDeviceUDIDHere` is the UDID you saw) to perform first-time setup. This requires the device to be connected via USB.
	  4. `sudo pkill usbmuxd` at the end.
2. `sudo -E su --preserve-environment UserNameHere` (where `UserNameHere` is a user created above) and then run one of the following in this shell to make a backup. The following commands don't require the device to be connected to the computer via USB, only to be plugged in and charging somewhere on the same local WiFi network.
   1. Run these as sudo the first time (as any user), then run them in the shell created above afterwards if needed:
	  1. To backup immediately once if it can connect and also repeating every day -- *not* dry run:
		  - `./backupMyIPhone.sh '' 1 0 0 'YourDeviceUDIDHere'`
	  2. Or: to backup immediately once if it can connect and also repeating every day -- dry run:
		  - `./backupMyIPhone.sh '' 1 0 1 'YourDeviceUDIDHere'`
	  3. Or: to backup via USB instead (it will start usbmuxd as root with sudo):
		  - `./backupMyIPhone.sh "" 1 0 0 'YourDeviceUDIDHere' 0 1
3. Run `./ibackup.sh` (with additional arguments like the above) for as many users as needed to make the backup daemons for each user. (They should all end up sharing the same usbmuxd instance.)

## Tools

- Debug how usb/WiFi connections are doing: `nix-shell`, then `sudo usbmuxd -vv --debug --debug`



Nvm:
1. Internal: `sudo ./ibackup.sh '' 1 0 8089 UserNameHere` to perform first-time setup. This requires the device to be connected via USB.
2. Internal: to backup as a daemon running now, which will additionally run at 12:01 AM *or* 24 hours from now, whichever is closest, repeatedly:
   - `./ibackup.sh YourDeviceUDIDHere 0 0 8089 UserNameHere` where `YourDeviceUDIDHere` is the device UDID from the output of the first-time setup above, and `UserNameHere` is a user created above.
2. Run a backup "daemon": `sudo su YourBackupUserHere -c "./backupMyIPhone.sh '' 1 0 1 'YourDeviceUDIDHere'"` where `YourBackupUserHere` is in the `iosbackup` group.
