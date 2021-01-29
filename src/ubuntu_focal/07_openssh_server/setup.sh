#!/bin/sh

export DEBIAN_FRONTEND=noninteractive

if dpkg -s openssh-server >/dev/null 2>&1; then
    echo "Nothing to do"
    exit 0
fi

apt-get -y install openssh-server
rm -v /etc/ssh/ssh_host_*
