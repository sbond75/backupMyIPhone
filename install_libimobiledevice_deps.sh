sudo apt-get update
sudo apt-get -y upgrade
#sudo apt-get -y install vim tmux git build-essential libxml2-dev python2.7 python2.7-dev fuse libtool autoconf libusb-1.0-0-dev libfuse-dev
sudo apt-get -y install vim tmux git build-essential libxml2-dev python3 python3-dev fuse libtool autoconf libusb-1.0-0-dev libfuse-dev

# https://github.com/libimobiledevice/libimobiledevice
sudo apt-get -y install \
     doxygen \
     cython \
     libssl-dev # Added to fix `error: OpenSSL support explicitly requested but OpenSSL could not be found`
