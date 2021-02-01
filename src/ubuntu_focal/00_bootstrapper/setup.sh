#!/bin/sh

tee /lib/systemd/system/vm-bootstrap.service >/dev/null <<EOF
[Unit]
Description=VM bootstrap script runner
DefaultDependencies=no
Wants=sysinit.target local-fs.target network.target
Before=sysinit.target
After=local-fs.target network.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'cd /boot/efi; mv vm-bootstrap.sh vm-bootstrap.env /dev/shm/ 2>/dev/null; cd /dev/shm; if test -f vm-bootstrap.sh -a -r vm-bootstrap.sh; then /bin/sh vm-bootstrap.sh >/var/log/vm-bootstrap.log 2>&1; fi'

[Install]
WantedBy=multi-user.target
EOF

systemctl enable vm-bootstrap.service
