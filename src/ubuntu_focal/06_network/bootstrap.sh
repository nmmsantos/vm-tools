#!/bin/sh

: ${IP=192.168.1.2}
: ${NETMASK=24}
: ${GATEWAY=192.168.1.1}
: ${DOMAIN=example.com}
: ${DNS=192.168.1.1}
: ${HOSTNAME=ubuntu}

# static hostname
tee /etc/hostname >/dev/null <<EOF
$HOSTNAME
EOF

# transient hostname
sysctl kernel.hostname=$HOSTNAME

tee /etc/hosts >/dev/null <<EOF
127.0.0.1       localhost
127.0.1.1       $HOSTNAME.$DOMAIN      $HOSTNAME

# The following lines are desirable for IPv6 capable hosts
::1     localhost ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
EOF

tee /etc/netplan/01-netcfg.yaml >/dev/null <<EOF
# This file describes the network interfaces available on your system
# For more information, see netplan(5).
network:
  version: 2
  renderer: networkd
  ethernets:
    eth0:
      addresses:
        - $IP/$NETMASK
      gateway4: $GATEWAY
      nameservers:
        search:
          - $DOMAIN
        addresses:
          - $DNS
EOF

netplan apply
