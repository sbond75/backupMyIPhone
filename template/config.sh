# This is an example file. Replace `config__drive` with your desired destination storage location. A directory `home` must exist on it, and that will be used to store backups. The backup script will create folders for the users made in `README.md` as needed to store backups for each user's devices, along with btrbk snapshots for each user's backups folder. This allows for incremental-style backups and requires `config__drive` to be a Btrfs filesystem.

# Destination drive for the backup. This must be a mountpoint (i.e., `mountpoint` command must return exit code 0 when run with this as an argument) and must be a Btrfs filesystem.
config__drive=/mnt/someMountPointHere
