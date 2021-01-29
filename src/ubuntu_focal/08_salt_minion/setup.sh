#!/bin/sh

export DEBIAN_FRONTEND=noninteractive

SALTSTACK_VERSION=3002
. /etc/os-release

if dpkg -s salt-minion >/dev/null 2>&1; then
    echo "Nothing to do"
    exit 0
fi

wget -qO- https://repo.saltstack.com/py3/ubuntu/$VERSION_ID/$ARCH/$SALTSTACK_VERSION/SALTSTACK-GPG-KEY.pub | apt-key add -

tee /etc/apt/sources.list.d/saltstack.list >/dev/null <<EOF
deb [arch=$ARCH] http://repo.saltstack.com/py3/ubuntu/$VERSION_ID/$ARCH/$SALTSTACK_VERSION $SUITE main
EOF

apt-get update

apt-get -y install salt-minion
