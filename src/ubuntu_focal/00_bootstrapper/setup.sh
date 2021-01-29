#!/bin/sh

tee /lib/systemd/system/vm-bootstrap.service >/dev/null <<EOF
[Unit]
Description=VM bootstrap script runner
DefaultDependencies=no
Wants=local-fs.target network.target
After=local-fs.target network.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'SH=/boot/efi/vm-bootstrap.sh; if test -f \$SH -a -r \$SH; then trap "rm \$SH" INT TERM EXIT; /bin/sh \$SH >/var/log/vm-bootstrap.log 2>&1; fi'

[Install]
WantedBy=multi-user.target
EOF

systemctl enable vm-bootstrap.service
