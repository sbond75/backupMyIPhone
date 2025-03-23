scriptDir="$(dirname "${BASH_SOURCE[0]}")"

cd "$scriptDir"
git submodule update --init --recursive

sudo apt install -y rsync smbclient cifs-utils lftp curlftpfs

# if using rclone instead of curlftpfs (newer version of rclone fixes TLS issues):
#sudo apt install -y rclone
mkdir iphone_libs
cd iphone_libs
wget https://downloads.rclone.org/v1.69.1/rclone-v1.69.1-linux-arm-v7.deb
sudo dpkg -i rclone-v1.69.1-linux-arm-v7.deb
cd ..

# Try `netcat` but it might be renamed now to `netcat-traditional` or `netcat-openbsd`.
sudo apt install -y netcat
exitCode="$?"
if [ "$exitCode" != "0" ]; then
    sudo apt install -y netcat-traditional
fi

# Setup and install usbmuxd, idevicebackup2, etc. imperatively:
bash "$scriptDir/install_libimobiledevice_deps.sh"
bash "$scriptDir/compile_libimobiledevice_imperatively.sh" 0

# if using pyftpsync instead of rclone/curlftpfs:
python3 -m venv .venv
#.venv/bin/pip install pyftpsync
.venv/bin/pip install ./pyftpsync

# Make users and groups
sudo useradd iosbackup_server
sudo groupadd iosbackup
sudo usermod -a -G iosbackup iosbackup_server
