#!/bin/sh

export DEBIAN_FRONTEND=noninteractive

if dpkg -s parted openssh-server >/dev/null 2>&1; then
    echo "Nothing to do"
    exit 0
fi

tee /lib/systemd/system/vm-bootstrap.service >/dev/null <<EOF
[Unit]
Description=VM bootstrap script runner
DefaultDependencies=no
Wants=network-pre.target systemd-modules-load.service local-fs.target
Before=network-pre.target
After=systemd-modules-load.service local-fs.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'SH=/boot/efi/vm-bootstrap.sh; if test -f \$SH -a -r \$SH; then trap "rm \$SH" INT TERM EXIT; /bin/sh \$SH; fi'

[Install]
WantedBy=multi-user.target
EOF

systemctl enable vm-bootstrap.service

# to support partition resizing
apt-get -y install parted

# to support remote logins
apt-get -y install openssh-server

rm -v /etc/ssh/ssh_host_*
