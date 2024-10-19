scriptDir="$(dirname "${BASH_SOURCE[0]}")"

sudo apt install -y rsync smbclient cifs-utils lftp curlftpfs

# Try `netcat` but it might be renamed now to `netcat-traditional` or `netcat-openbsd`.
sudo apt install -y netcat
exitCode="$?"
if [ "$exitCode" != "0" ]; then
    sudo apt install -y netcat-traditional
fi

# Setup and install usbmuxd, idevicebackup2, etc. imperatively:
bash "$scriptDir/install_libimobiledevice_deps.sh"
bash "$scriptDir/compile_libimobiledevice_imperatively.sh" 0
