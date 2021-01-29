#!/bin/sh

export DEBIAN_FRONTEND=noninteractive

if dpkg -s linux-image-virtual-hwe-20.04-edge >/dev/null 2>&1; then
    echo "Nothing to do"
    exit 0
fi

apt-get -y install linux-image-virtual-hwe-20.04-edge grub-pc-
