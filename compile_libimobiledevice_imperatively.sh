# This file is part of instructions in ibackupClient.sh and is intended to be run on a Raspberry Pi.
# Based on https://gist.github.com/kfatehi/8922430

set -ex

installDepsWithApt="$1" # Optional; 0 to not install them. Default is to install them.

scriptDir="$(dirname "${BASH_SOURCE[0]}")"
if [ ! -e iphone_libs ]; then
    if [ "$installDepsWithApt" != "0" ]; then
	bash "$scriptDir/install_libimobiledevice_deps.sh"
    fi

    mkdir iphone_libs && cd iphone_libs

    git clone https://github.com/libimobiledevice/libplist.git
    git clone https://github.com/libimobiledevice/libusbmuxd.git
    git clone https://github.com/libimobiledevice/usbmuxd.git
    git clone https://github.com/libimobiledevice/libimobiledevice.git
    git clone https://github.com/libimobiledevice/ifuse.git
    git clone https://github.com/libimobiledevice/libimobiledevice-glue.git
else
    cd iphone_libs
fi

if [ -z "$(grep -F "export PKG_CONFIG_PATH=/usr/local/lib/pkgconfig" /etc/bash.bashrc || true)" ]; then # Add if needed:
    export PKG_CONFIG_PATH=/usr/local/lib/pkgconfig
    echo "export PKG_CONFIG_PATH=/usr/local/lib/pkgconfig" | sudo tee -a /etc/bash.bashrc
fi

if [ ! -e /usr/local/lib/libplist-2.0.a ]; then
    cd libplist && ./autogen.sh --without-cython && make && sudo make install && cd ..
fi
if [ ! -e /usr/local/lib/libimobiledevice-glue-1.0.a ]; then
    cd libimobiledevice-glue && ./autogen.sh && make && sudo make install && cd ..
fi
if [ ! -e /usr/local/lib/libusbmuxd-2.0.a ]; then
    cd libusbmuxd && ./autogen.sh && make && sudo make install && cd ..
fi
if [ ! -e /usr/local/bin/idevicebackup2 ]; then
    cd libimobiledevice && ./autogen.sh && make && sudo make install && cd ..
fi
if [ ! -e /usr/local/sbin/usbmuxd ]; then
    cd usbmuxd && ./autogen.sh && make && sudo make install && cd ..
fi
if [ ! -e /usr/local/bin/ifuse ]; then
    cd ifuse && ./autogen.sh && make && sudo make install && cd ..
fi

if [ -z "$(getent group usbmux || true)" ]; then # Add if needed:
    # Add usbmux group
    sudo groupadd -g 140 usbmux
    # Add usbmux user
    sudo useradd -c 'usbmux user' -u 140 -g usbmux -d / -s /sbin/nologin usbmux
    # Make usbmux user have a locked password (can't be changed by the user)
    sudo passwd -l usbmux
fi

if [ -z "$(grep -F "/usr/local/lib" /etc/ld.so.conf.d/libimobiledevice-libs.conf || true)" ]; then # Add if needed:
    echo /usr/local/lib | sudo tee /etc/ld.so.conf.d/libimobiledevice-libs.conf
fi

# https://github.com/libimobiledevice/libimobiledevice/issues/1002 -- fixes "libimobiledevice-1.0.so.6: cannot open shared object file: No such file or directory" (when running something like `ideviceinfo`):
sudo ldconfig
