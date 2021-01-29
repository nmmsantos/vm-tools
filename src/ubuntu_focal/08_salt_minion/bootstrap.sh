#!/bin/sh

: ${SALT_MASTER_IP=$IP}
: ${SALT_MINION_ID=$HOSTNAME}

tee -a /etc/hosts >/dev/null <<EOF

$SALT_MASTER_IP       salt
EOF

echo "$SALT_MINION_ID" >/etc/salt/minion_id
