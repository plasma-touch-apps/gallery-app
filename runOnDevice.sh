#!/bin/sh
CODE_DIR=gallery
USER=phablet
USER_ID=32011
PASSWORD=phablet
PACKAGE=gallery-app
BINARY=gallery-app
TARGET_IP=127.0.0.1
TARGET_SSH_PORT=2222
TARGET_DEBUG_PORT=3768
RUN_OPTIONS="--startup-timer --desktop_file_hint=/usr/share/applications/gallery-app.desktop"
# -qmljsdebugger=port:$TARGET_DEBUG_PORT"
SETUP=false
SUDO="echo $PASSWORD | sudo -S"

usage() {
    echo "usage: run_on_device [OPTIONS]\n"
    echo "Script to setup a build environment for the gallery and sync build and run it on the device\n"
    echo "OPTIONS:"
    echo "  -s, --setup   Setup the build environment"
    echo ""
    echo "IMPORTANT:"
    echo " * Make sure to have the networking and PPAs setup on the device beforehand (phablet-deploy-networking && phablet-ppa-fetch)."
    echo " * Execute that script from a directory containing a branch the shell code."
    exit 1
}

exec_with_ssh() {
    ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -t $USER@$TARGET_IP -p $TARGET_SSH_PORT "bash -ic \"$@\""
}

exec_with_adb() {
    adb shell chroot /data/ubuntu /usr/bin/env -i PATH=/bin:/usr/bin:/sbin:/usr/sbin:/tools/bin "$@"
}

adb_root() {
    adb root
    adb wait-for-device
}

install_ssh_key() {
    adb shell "apt-get install openssh-server"
    ssh-keygen -R $TARGET_IP
    HOME_DIR=/data/ubuntu/home/phablet
    adb push ~/.ssh/id_rsa.pub $HOME_DIR/.ssh/authorized_keys
    adb shell chown $USER_ID:$USER_ID $HOME_DIR/.ssh
    adb shell chown $USER_ID:$USER_ID $HOME_DIR/.ssh/authorized_keys
    adb shell chmod 700 $HOME_DIR/.ssh
    adb shell chmod 600 $HOME_DIR/.ssh/authorized_keys
}

install_dependencies() {
    exec_with_adb apt-get -y install openssh-server
    exec_with_ssh $SUDO apt-get -y install build-essential rsync bzr ccache gdb libglib2.0-bin
    exec_with_ssh $SUDO add-apt-repository -y ppa:canonical-qt5-edgers/qt5-proper
    exec_with_ssh $SUDO add-apt-repository -s -y ppa:phablet-team/ppa
    exec_with_ssh $SUDO apt-get update
    exec_with_ssh $SUDO apt-get -y build-dep $PACKAGE
}

reset_screen_powerdown() {
    exec_with_ssh $SUDO dbus-launch gsettings set com.canonical.powerd activity-timeout 600
    exec_with_ssh $SUDO sudo initctl restart powerd
}

setup_adb_forwarding() {
    adb forward tcp:$TARGET_SSH_PORT tcp:22
    adb forward tcp:$TARGET_DEBUG_PORT tcp:$TARGET_DEBUG_PORT
}

sync_code() {
    bzr export --uncommitted --format=dir /tmp/$CODE_DIR
    rsync -crlOzv -e "ssh -p $TARGET_SSH_PORT -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no" /tmp/$CODE_DIR/ $USER@$TARGET_IP:$CODE_DIR/
    rm -rf /tmp/$CODE_DIR
}

build() {
    exec_with_ssh PATH=/usr/lib/ccache:$PATH "cd $CODE_DIR/ && PATH=/usr/lib/ccache:$PATH cmake -DCMAKE_BUILD_TYPE=debug . && PATH=/usr/lib/ccache:$PATH make -j 2"
}

run() {
    adb shell pkill $BINARY
    exec_with_ssh "cd $CODE_DIR/src && ./$BINARY $RUN_OPTIONS"
}

set -- `getopt -n$0 -u -a --longoptions="setup,help" "sh" "$@"`

# FIXME: giving incorrect arguments does not call usage and exit
while [ $# -gt 0 ]
do
    case "$1" in
       -s|--setup)   SETUP=true;;
       -h|--help)    usage;;
       --)           shift;break;;
    esac
    shift
done

adb_root
setup_adb_forwarding

if $SETUP; then
    echo "Setting up environment for building shell.."
    install_ssh_key
    install_dependencies
    reset_screen_powerdown
    sync_code
else
    echo "Transferring code.."
    sync_code
    echo "Building.."
    build
    echo "Running.."
    run
fi
