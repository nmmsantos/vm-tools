#!/bin/sh

set -e

if test ! -f k3os.iso; then
    printf "k3os.iso doesn't exist\n" >&2
    exit 1
fi

CONFIG=$(mktemp)

trap "rm $CONFIG" INT TERM EXIT

tee $CONFIG >/dev/null <<EOF
# K3S_SERVER=https://10.0.0.62:6443
# sudo cat /var/lib/rancher/k3s/server/node-token
K3S_TOKEN=0aYIcZtkugkp0GvLBHC6FnM0OplLvBum
VM_HOSTNAME=k3os-
VM_IP=10.0.0.
VM_MEMORY_MB=8192
VM_HDD_GB=20
VM_VCPUS=1
VM_CORES=2
VM_THREADS=1
VM_NIC=lagg0
VM_MAC=02:00:00$(hexdump -n3 -e '/1 ":%02X"' /dev/urandom)
VM_NETMASK=255.255.255.0
VM_GATEWAY=10.0.0.1
VM_DNS=10.0.0.2
VM_SHUTDOWN_TIMEOUT=90
VM_DATASET=nvme-01-r0-wdblue/vms/\$VM_HOSTNAME-hdd
VM_NAME=\$(printf "%s" \$VM_HOSTNAME | sed 's|[^a-zA-Z0-9]|_|g')
VM_DESCRIPTION="\$VM_HOSTNAME - \$VM_IP - \$VM_MAC - \$VM_DATASET"
VM_SSH_KEY="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDT2l7FkBAZeZHDhB7AwT+Vx6pKjIVBe2fgaMb6x3yoi2iwRsxygnDnkX5CrVsSE8jhUqoZ8k7\
5U4TJyKNimCo+9LdIiDjxwOrRPAXjxEbyvfrISlpdoyOZsRbU/wguXvp7Wa2PEgoQFZa8reetOX8hhgVviO5LTZkZkJxUcrdNkxLJ/GeyYTDadt5OnbfuqYcNLm\
gt1C96fXW0oZaV/bB5WAA5mLEEzS9FH5jxKI4xLQNBSM3vzVJ2sPLbZ/vHhvthl3/NiSVBXjnX+OA1wEw5+dNs+1eNJCTRt8ba6ye2mCGmpIxsq3nNJkOIf/SYq\
eELN8lAKejlU36SVZ31/ZvqCWlChhoaTJ0Ck022Pgkbr8miP2kH1LgmNNide5rgF5i+TlFBJg6i7gpudeXqxu0eVtHDueT3615o8c1thStK4vZF+zRlbUoHj/ci\
LGnU+ZpoAbuwK7HE235bITKcuBJ235Jb5aNd5oUnqQqU4+z249ts9KQYmDbxfVf4cgLB0ZUriJjYZBkTNgaBLkVbwWUuYX8pErgcep3zkUzw+alVVLYvbYPMlFv\
S5BiE2HRHy7JPBQtOqA2RuFsH6/sqEPNqSMwGLvjwIvwvP5PmHPJOOi8Nz3YxpsfWB+pupVL1xE/3ZtTa17CCrOguEsfK0VDDuXy3xIi9cnt4hJ+yP8+TLw=="
TRUENAS_IP=10.0.0.61
TRUENAS_KEY=1-RNBKARjaHsQdTOAccoZuhxaF01L7kCLz8uPw1R7sC82K8ueQqMXD1GyRRL81R41x
EOF

nano $CONFIG

eval "$(cat $CONFIG)"

# http://$TRUENAS_IP/api/docs/

api() {
    curl -fsSLX $1 http://$TRUENAS_IP/api/v2.0$2 \
        -H "Authorization: Bearer $TRUENAS_KEY" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        --data-binary @- </dev/stdin

    sleep 1
}

vm_start() {
    printf "Starting VM\n"
    api POST /vm/id/$1/start </dev/null >/dev/null
}

vm_status() {
    api POST /vm/id/$1/status </dev/null | jq -r '.state'
}

# api DELETE /vm/id/1 >/dev/null <<EOF
# {
#     "zvols": true,
#     "force": true
# }
# EOF

printf "Creating VM\n"

api POST /vm >$CONFIG <<EOF
{
    "name": "$VM_NAME",
    "description": "$VM_DESCRIPTION",
    "vcpus": $VM_VCPUS,
    "cores": $VM_CORES,
    "threads": $VM_THREADS,
    "memory": $VM_MEMORY_MB,
    "autostart": true,
    "time": "LOCAL",
    "bootloader": "UEFI",
    "shutdown_timeout": $VM_SHUTDOWN_TIMEOUT,
    "devices": [
        {
            "dtype": "NIC", "order": 1000,
            "attributes": { "type": "VIRTIO", "mac": "$VM_MAC", "nic_attach": "$VM_NIC" }
        },
        {
            "dtype": "DISK", "order": 1001,
            "attributes": { "type": "VIRTIO", "create_zvol": true, "zvol_name": "$VM_DATASET", "zvol_volsize": $(printf "%d * 1073741824\n" $VM_HDD_GB | bc) }
        },
        {
            "dtype": "CDROM", "order": 1002,
            "attributes": { "path": "/mnt/hdd-01-r1-wdred/home/nuno/k3os.iso" }
        }
    ]
}
EOF

# # "path": "$(readlink -f k3os.iso)"

eval "$(cat $CONFIG | jq -r '"
VM_ID=\(.id)
VM_CDROM_ID=\(.devices[] | select(.dtype=="CDROM").id)
VM_HDD_PATH=\(.devices[] | select(.dtype=="DISK").attributes.path)
"')"

vm_start $VM_ID

printf "Installing K3OS\n"

if test -n "$K3S_SERVER"; then
    K3S_SERVER="server_url: $K3S_SERVER"
fi

tee /dev/null <<EOF | socat - tcp4-listen:54321,reuseaddr >/dev/null
HTTP/1.1 200 OK
Content-Type: text/yaml

ssh_authorized_keys:
  - $VM_SSH_KEY
hostname: $VM_HOSTNAME
write_files:
  - path: /var/lib/connman/default.config
    content: |
      [service_eth0]
      Type=ethernet
      IPv4=$VM_IP/$VM_NETMASK/$VM_GATEWAY
      IPv6=off
      Nameservers=$VM_DNS
k3os:
  dns_nameservers:
    - $VM_DNS
  ntp_servers:
    - 0.pool.ntp.org
    - 1.pool.ntp.org
    - 2.pool.ntp.org
  $K3S_SERVER
  token: $K3S_TOKEN
EOF

printf "Waiting for installation to finish\n"

while test "$(vm_status $VM_ID)" != "STOPPED"; do :; done

printf "Finishing installation\n"

api DELETE /vm/device/id/$VM_CDROM_ID </dev/null >/dev/null

vm_start $VM_ID
