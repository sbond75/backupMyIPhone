# This is an example file. Replace `config__drive` with your desired destination storage location. A directory `home` must exist on it, and that will be used to store backups. The backup script will create folders for the users made in `README.md` as needed to store backups for each user's devices, along with btrbk snapshots for each user's backups folder. This allows for incremental-style backups and requires `config__drive` to be a Btrfs filesystem.

# Destination drive for the backup. This must be a mountpoint (i.e., `mountpoint` command must return exit code 0 when run with this as an argument) and must be a Btrfs filesystem.
config__drive=/mnt/someMountPointHere

# For remote backups, i.e. when run from a client (remotely transmitting a backup made from an iOS device connected to the "client" computer which is sent to a "server" computer running ibackupServer.sh) #
# For remote backups: destination directory for the backup on the client
config__clientDirectory=/home/pi/Projects/backupMyIPhone_clientDirectory

# For remote backups: this is the path (on the client) to the SSL certificate of the server for vsftpd (FTP) connections.
config__certPath=/home/pi/Projects/server_ftp.cert
# For remote backups: server IP address or hostname
config__host=192.168.1.x

# For remote backups, a Linux user account like userNameHere (which is usually something followed by the `_iosbackup` suffix) gotten from udidToFolderLookupTable.py will get the suffix `_ftp` added (i.e. it becomes `userNameHere_ftp`) as the username for FTP login. The password will be gotten from one of the below which are of the form `config__usernameForFTP=passwordForFTPHere`:
config__userNameHere_iosbackup_ftp='passwordForFTPHere'
config__user2NameHere_iosbackup_ftp='password2ForFTPHere'
# #
