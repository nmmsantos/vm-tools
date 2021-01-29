#!/bin/sh

: ${SSH_KEY=}

# generate ssh host keys
dpkg-reconfigure openssh-server

if test -z "$SSH_KEY"; then
    exit 0
fi

mkdir -p /root/.ssh
chmod 700 /root/.ssh

tee /root/.ssh/authorized_keys >/dev/null <<EOF
$SSH_KEY
EOF

chmod 600 /root/.ssh/authorized_keys
