#!/bin/sh

# resize root partition
sync; echo "- +" | sfdisk -f --no-reread $(lsblk -lnpo PKNAME,MOUNTPOINT | awk '$2=="/" {{print $1}}') -N 2
sync; partprobe
sync; resize2fs $(lsblk -lnpo PATH,MOUNTPOINT | awk '$2=="/" {{print $1}}')
sync

# configure network
tee /etc/netplan/01-netcfg.yaml >/dev/null <<EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    eth0:
      addresses:
        - {ip}/{netmask}
      gateway4: {gateway}
      nameservers:
        search:
          - {domain}
        addresses:
          - {dns}
EOF

netplan generate

hostnamectl set-hostname {hostname}

tee /etc/hosts >/dev/null <<EOF
127.0.0.1       localhost
127.0.1.1       {hostname}.{domain}      {hostname}
{salt_master_ip}       salt

# The following lines are desirable for IPv6 capable hosts
::1     localhost ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
EOF

# configure salt minion
echo {minion_id} >/etc/salt/minion_id

# configure ssh
mkdir -p /root/.ssh
chmod 700 /root/.ssh

tee /root/.ssh/authorized_keys >/dev/null <<EOF
{ssh_key}
EOF

chmod 600 /root/.ssh/authorized_keys

# generate ssh keys
dpkg-reconfigure openssh-server
