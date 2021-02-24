#!/bin/sh

: ${SALT_MASTER_IP=$IP}
: ${SALT_MINION_ID=$HOSTNAME}

sed -i \
    -e 's/master: .*/master: '$SALT_MASTER_IP'/' \
    -e 's/id: .*/id: '$SALT_MINION_ID'/' \
    /opt/salt/etc/salt/minion.d/custom.conf
