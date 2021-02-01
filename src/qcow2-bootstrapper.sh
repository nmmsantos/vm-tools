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

check_tool blkid
check_tool chroot
check_tool dd
check_tool debootstrap
check_tool kpartx
check_tool mkfs.ext4
check_tool mktemp
check_tool parted
check_tool qemu-img
check_tool virt-sparsify

if test $# -ne 2 -o ! -d "$1"; then
    echo "usage: $(basename $0) SCRIPTS_DIR QCOW2_FILE"
    exit 0
fi

SCRIPTS_DIR="$1"
VHDD_FILE_OUTPUT="$2"

# if modprobe --first-time -n nbd 2>/dev/null; then
#     info "Inserting nbd kernel module"
#     modprobe --first-time nbd max_part=8
#     cleanup_push "info 'Removing nbd kernel module'; retry 'modprobe -r --first-time nbd'"
# fi

# for NBD_DEVICE in $(ls -v1 /sys/class/block | grep ^nbd); do
#     if test $(cat /sys/class/block/$NBD_DEVICE/size) -eq 0; then
#         break
#     fi
# done

# NBD_DEVICE=/dev/$(basename $NBD_DEVICE)

# info "Connecting $VHDD_FILE_OUTPUT to $NBD_DEVICE"
# qemu-nbd --connect $NBD_DEVICE $VHDD_FILE_OUTPUT
# cleanup_push "info 'Disconnecting $VHDD_FILE_OUTPUT from $NBD_DEVICE'; retry 'qemu-nbd --disconnect $NBD_DEVICE'"

WORKDIR="$(mktemp -d)"
info "Created workdir $WORKDIR"
cleanup_push "info 'Removing workdir $WORKDIR'; rm -rf $WORKDIR"

info "Mounting tmpfs on $WORKDIR"
mount -t tmpfs -o size=2050m tmpfs $WORKDIR
cleanup_push "info 'Unmounting tmpfs from $WORKDIR'; retry 'umount $WORKDIR'"

VHDD_FILE=$WORKDIR/raw.img

if test -f "$VHDD_FILE_OUTPUT"; then
    info "Copying $VHDD_FILE_OUTPUT to $VHDD_FILE"
    qemu-img convert -f qcow2 -O raw "$VHDD_FILE_OUTPUT" $VHDD_FILE
else
    info "Creating vhdd $VHDD_FILE"
    dd if=/dev/zero of=$VHDD_FILE bs=1M count=2048

    parted -s -a opt $VHDD_FILE -- \
        mklabel gpt \
        mkpart primary fat32 0% 512M \
        mkpart primary ext4 512M 100% \
        set 1 boot on \
        print
fi

info "Creating device maps for $VHDD_FILE"
VHDD_LOOP=$(kpartx -l $VHDD_FILE | sed -n 1p)
EFI_PART=/dev/mapper/$(echo "$VHDD_LOOP" | awk '{print $1}')
VHDD_LOOP=$(kpartx -l $VHDD_FILE | sed -n 2p)
ROOT_PART=/dev/mapper/$(echo "$VHDD_LOOP" | awk '{print $1}')
VHDD_LOOP=$(echo "$VHDD_LOOP" | awk '{print $5}')
kpartx -a $VHDD_FILE
cleanup_push "info 'Removing device maps from $VHDD_FILE'; retry 'kpartx -d $VHDD_FILE >/dev/null'"
# EFI_PART=$(losetup -v -f --show $EFI_PART)
# cleanup_push "retry 'losetup -d $EFI_PART'"
info "Device: $VHDD_LOOP"
info "EFI Partition: $EFI_PART"
info "Root Partition: $EFI_PART"

if ! file -sL $EFI_PART | grep "DOS/MBR boot sector" >/dev/null; then
    info "Creating fat32 filesystem on $EFI_PART"
    mkfs.fat -F32 -v -n EFI $EFI_PART
fi

if ! file -sL $ROOT_PART | grep "ext4 filesystem" >/dev/null; then
    info "Creating ext4 filesystem on $ROOT_PART"
    mkfs.ext4 -L OS $ROOT_PART
fi

EFI_PART_UUID=$(blkid -s UUID -o value $EFI_PART)
ROOT_PART_UUID=$(blkid -s UUID -o value $ROOT_PART)

ROOTFS=$WORKDIR/rootfs
mkdir -p $ROOTFS

info "Mounting $ROOT_PART on $ROOTFS"
mount $ROOT_PART $ROOTFS
cleanup_push "info 'Unmounting $ROOT_PART from $ROOTFS'; retry 'umount $ROOTFS'"

: ${DISTRO_UBUNTU=1}
: ${ARCH=amd64}

# ls -1 /usr/share/debootstrap/scripts/

if test $DISTRO_UBUNTU -eq 1; then
    : ${SUITE=focal}
    : ${COMPONENTS=main,restricted,multiverse,universe}
    : ${MIRROR=http://archive.ubuntu.com/ubuntu}
else
    : ${SUITE=buster}
    : ${COMPONENTS=main,contrib,non-free}
    : ${MIRROR=https://deb.debian.org/debian}
fi

if test "$(. $ROOTFS/etc/os-release 2>/dev/null; echo $VERSION_CODENAME)" != "$SUITE"; then
    info "Bootstrapping $SUITE-$ARCH to $ROOTFS from $MIRROR"
    debootstrap --arch=$ARCH --components=$COMPONENTS $SUITE $ROOTFS $MIRROR
fi

mkdir -p $ROOTFS/boot/efi

info "Mounting $EFI_PART on $ROOTFS/boot/efi"
mount $EFI_PART $ROOTFS/boot/efi
cleanup_push "info 'Unmounting $EFI_PART from $ROOTFS/boot/efi'; retry 'umount $ROOTFS/boot/efi'"

info "Mounting proc on $ROOTFS/proc"
mount -t proc proc $ROOTFS/proc
cleanup_push "info 'Unmounting proc from $ROOTFS/proc'; retry 'umount $ROOTFS/proc'"

info "Mounting sysfs on $ROOTFS/sys"
mount -t sysfs sys $ROOTFS/sys
cleanup_push "info 'Unmounting sysfs from $ROOTFS/sys'; retry 'umount $ROOTFS/sys'"

info "Bind mounting /dev on $ROOTFS/dev"
mount -o bind /dev $ROOTFS/dev
cleanup_push "info 'Unmounting /dev from $ROOTFS/dev'; retry 'umount $ROOTFS/dev'"

info "Bind mounting /dev/pts on $ROOTFS/dev/pts"
mount -o bind /dev/pts $ROOTFS/dev/pts
cleanup_push "info 'Unmounting /dev/pts from $ROOTFS/dev/pts'; retry 'umount $ROOTFS/dev/pts'"

VM_BOOTSTRAP=$ROOTFS/boot/efi/vm-bootstrap.sh
>$VM_BOOTSTRAP

for SCRIPT_DIR in $(ls -v1 "$SCRIPTS_DIR"); do
    SETUP="$SCRIPTS_DIR/$SCRIPT_DIR/setup.sh"

    if test -f "$SETUP" -a -x "$SETUP" -a -r "$SETUP"; then
        cp "$SETUP" $ROOTFS/setup
        cleanup_push "rm $ROOTFS/setup"

        info "Executing $SETUP on $ROOTFS"
        SUITE=$SUITE \
            MIRROR=$MIRROR \
            ARCH=$ARCH \
            EFI_PART_UUID=$EFI_PART_UUID \
            ROOT_PART_UUID=$ROOT_PART_UUID \
            VHDD_LOOP=$VHDD_LOOP \
            EFI_PART=$EFI_PART \
            ROOT_PART=$ROOT_PART \
            chroot $ROOTFS /setup

        eval "$(cleanup_peek)"; cleanup_pop # current script
    fi

    BOOTSTRAP="$SCRIPTS_DIR/$SCRIPT_DIR/bootstrap.sh"

    if test -f "$BOOTSTRAP" -a -x "$BOOTSTRAP" -a -r "$BOOTSTRAP"; then
        info "Appending $BOOTSTRAP to $VM_BOOTSTRAP"
        cat "$BOOTSTRAP" >>$VM_BOOTSTRAP
    fi
done

eval "$(cleanup_peek)"; cleanup_pop # /dev/pts
eval "$(cleanup_peek)"; cleanup_pop # /dev
eval "$(cleanup_peek)"; cleanup_pop # /sys
eval "$(cleanup_peek)"; cleanup_pop # /proc
eval "$(cleanup_peek)"; cleanup_pop # /rootfs/boot/efi
eval "$(cleanup_peek)"; cleanup_pop # /rootfs
eval "$(cleanup_peek)"; cleanup_pop # kpartx

info "Exporting $VHDD_FILE to $VHDD_FILE_OUTPUT"
virt-sparsify --format raw --convert qcow2 --compress $VHDD_FILE "$VHDD_FILE_OUTPUT"
