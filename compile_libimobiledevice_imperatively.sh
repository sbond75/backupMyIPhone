# This file is part of instructions in ibackupClient.sh and is intended to be run on a Raspberry Pi.
# From https://gist.github.com/kfatehi/8922430

sudo apt-get update
sudo apt-get -y upgrade
sudo apt-get -y install vim tmux git build-essential libxml2-dev python2.7 python2.7-dev fuse libtool autoconf libusb-1.0-0-dev libfuse-dev

mkdir iphone_libs && cd iphone_libs

git clone https://github.com/libimobiledevice/libplist.git
git clone https://github.com/libimobiledevice/libusbmuxd.git
git clone https://github.com/libimobiledevice/usbmuxd.git
git clone https://github.com/libimobiledevice/libimobiledevice.git
git clone https://github.com/libimobiledevice/ifuse.git

export PKG_CONFIG_PATH=/usr/local/lib/pkgconfig
echo "export PKG_CONFIG_PATH=/usr/local/lib/pkgconfig" | sudo tee -a /etc/bash.bashrc

cd libplist && ./autogen.sh && make && sudo make install && cd ..
cd libusbmuxd && ./autogen.sh && make && sudo make install && cd ..
cd libimobiledevice && ./autogen.sh && make && sudo make install && cd ..
cd usbmuxd && ./autogen.sh && make && sudo make install && cd ..
cd ifuse && ./autogen.sh && make && sudo make install && cd ..

groupadd -g 140 usbmux &>/dev/null
useradd -c 'usbmux user' -u 140 -g usbmux -d / -s /sbin/nologin usbmux &>/dev/null
passwd -l usbmux &>/dev/null

echo /usr/local/lib | sudo tee /etc/ld.so.conf.d/libimobiledevice-libs.conf
sudo ldconfig
