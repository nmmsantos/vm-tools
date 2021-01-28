#!/bin/sh

set -e

trap "eval \"\$S_CLEANUP\"" INT TERM EXIT

cleanup_push() {
    S_CLEANUP="$1; >/dev/null; $S_CLEANUP"
}

cleanup_peek() {
    echo "$S_CLEANUP" | awk '{print substr($0, 0, index($0, "; >/dev/null; ") - 1)}'
}

cleanup_pop() {
    S_CLEANUP="$(echo "$S_CLEANUP" | awk '{print substr($0, index($0, "; >/dev/null; ") + 14)}')"
}

info() {
    echo "\033[32m$1\e[0m"
}

error() {
    echo "\033[31m$1\e[0m"
}

check_tool() {
    if ! which $1 >/dev/null; then
        error "error: command '$1' not found"
        exit 1
    fi
}

retry() {
    local i

    for i in 0 1 2 3 5; do
        sleep $i
        if eval "$1"; then
            return
        fi
    done

    error "error: command '$1' aborted after $i failed retries"
    return 1
}

check_tool e2fsck
check_tool parted
check_tool pvesm
check_tool qm
check_tool resize2fs
check_tool seq

if test $# -ne 4; then
    echo "usage: $(basename $0) QCOW2_FILE STORAGE [+]SIZE[KMGT] MINION_ID"
    exit 0
fi

QCOW2_FILE="$1"
STORAGE="$2"
SIZE="$3"
MINION_ID="$4"

if test ! -f "$QCOW2_FILE"; then
    error "error: invalid QCOW2_FILE $QCOW2_FILE"
    exit 1
fi

if ! pvesm status -content images -storage "$STORAGE" >/dev/null 2>&1; then
    error "error: invalid STORAGE $STORAGE"
    exit 1
fi

VM_IDS="$(qm list | tail -n +2 | awk '{print $1}')"

for VM_ID in $(seq 100 10000); do
    if ! echo "$VM_IDS" | grep ^$VM_ID$ >/dev/null; then
        break
    fi
done

MAC=02:$(printf '%010d' $VM_ID | sed 's/../&:/g;s/:$//')
# IP=10.0.0.$(echo "if($VM_ID>150) 150 else $VM_ID" | bc)
# GATEWAY=$(ip route get 1.1.1.1 | grep -Po '(?<=(via )).*(?= dev)')
BRIDGE=$(ip route get 1.1.1.1 | grep -Po '(?<=(dev )).*(?= src| proto)')
# IP_CIDR=$(ip addr show $BRIDGE | grep -Po '(?<=(inet )).*(?= brd)' | sed 's|.*\(/.*\)|'$IP'\1|')
# TEMPLATE="$(dirname "$(readlink -fn "$0")")/template-ubuntu-focal.qcow2"

info "Creating VM $VM_ID for minion $MINION_ID with MAC address $MAC"
qm create \
    $VM_ID \
    --agent 1 \
    --balloon 512 --memory 1024 \
    --boot c \
    --bootdisk virtio0 \
    --cpu host,flags=+aes \
    --hotplug 0 \
    --machine q35 \
    --name $MINION_ID \
    --net0 virtio=$MAC,bridge=$BRIDGE \
    --ostype l26 \
    --scsihw virtio-scsi-single \
    --serial0 socket \
    --sockets 1 --cores 2 \
    --tablet 0 \
    --vga none

info "Importing disk $QCOW2_FILE to $STORAGE"
qm importdisk $VM_ID $QCOW2_FILE $STORAGE
qm set $VM_ID --virtio0 $STORAGE:vm-$VM_ID-disk-0

DISK=$(pvesm path $STORAGE:vm-$VM_ID-disk-0)
PART=$DISK-part1

info "Searching for partitions on $DISK"
partprobe $DISK

if test "$SIZE" != "0"; then
    info "Resizing $PART to $SIZE"
    qm resize $VM_ID virtio0 $SIZE
    parted -sa optimal $DISK resizepart 1 100% print
    e2fsck -f $PART
    resize2fs $PART
fi

info "Mounting $PART on /mnt"
mount $PART /mnt
cleanup_push "info 'Unmounting $PART from /mnt'; retry 'umount /mnt'"

: ${SALT_MASTER=10.0.0.100}
: ${SALT_MASTER_FINGERPRINT=7a:db:dc:9d:f6:6a:e5:02:23:77:72:3f:33:7e:f9:60:45:ab:e7:11:84:4b:88:fc:01:6f:ae:8d:5a:e3:02:89}

info "Configuring salt master ip $SALT_MASTER"
sed -i '/127.0.1.1/a'"$(printf '%-15s' "$SALT_MASTER")"' salt' /mnt/etc/hosts

info "Configuring salt master fingerprint $SALT_MASTER_FINGERPRINT"
sed -Ei 's/#?(master_finger:).*/\1 '\'$SALT_MASTER_FINGERPRINT\''/' /mnt/etc/salt/minion

info "Configuring salt minion ID $MINION_ID"
tee /mnt/etc/salt/minion_id >/dev/null <<EOF
$MINION_ID
EOF

rm -f \
    /mnt/etc/salt/pki/minion/minion.pem \
    /mnt/etc/salt/pki/minion/minion.pub

# qemu-img convert -O qcow2 -f raw $(pvesm path nvme-wd:vm-100-disk-0) output.qcow2

# # list all keys
# salt-key -l all
# # list all fingerprints
# salt-key -F
# # accept a key
# salt-key -a <key>
# # delete a key
# salt-key -d <key>

# salt '*' saltutil.refresh_pillar
# salt '*' pillar.items
# salt '*' state.apply network test=True
# salt '*' grains.items
# salt '*' cmd.run 'salt-minion --versions-report'
