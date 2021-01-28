#!/bin/sh

export DEBIAN_FRONTEND=noninteractive

tee /etc/netplan/01-netcfg.yaml >/dev/null <<EOF
# This file describes the network interfaces available on your system
# For more information, see netplan(5).
network:
  version: 2
  renderer: networkd
  ethernets:
    eth0:
      dhcp4: yes
EOF

tee /etc/hosts >/dev/null <<EOF
127.0.0.1       localhost
127.0.1.1       ubuntu.example.com      ubuntu

# The following lines are desirable for IPv6 capable hosts
::1     localhost ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
EOF

tee /etc/hostname >/dev/null <<EOF
ubuntu
EOF
