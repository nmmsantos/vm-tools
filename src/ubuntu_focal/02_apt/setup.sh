#!/bin/sh

export DEBIAN_FRONTEND=noninteractive

OLD_CHECKSUM="$(sha1sum /etc/apt/sources.list)"

tee /etc/apt/sources.list >/dev/null <<EOF
deb $MIRROR $SUITE main restricted universe multiverse
deb $MIRROR $SUITE-updates main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu $SUITE-security main restricted universe multiverse
deb http://archive.canonical.com/ubuntu $SUITE partner
EOF

if echo "$OLD_CHECKSUM" | sha1sum -c --status; then
    echo "Nothing to do"
    exit 0
fi

apt-get update
apt-mark showmanual | grep -vE 'ubuntu-minimal' | xargs apt-mark auto
apt-get -y --purge autoremove
apt-get -y dist-upgrade
