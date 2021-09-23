#!/bin/sh
#https://willhaley.com/blog/custom-debian-live-environment/

set -e

for cmd in debootstrap chroot mksquashfs; do
    if ! which $cmd >/dev/null; then
        printf "command '%s' is missing\n" $cmd >&2
        exit 1
    fi
done

unset cmd

fss="$(awk '{print $NF}' /proc/filesystems)"

for fs in squashfs overlay; do
    if ! printf '%s' "$fss" | grep "^$fs" >/dev/null; then
        printf "cannot mount '%s' filesystem\n" $fs >&2
        exit 1
    fi
done

unset fss fs

set --
trap 'for cleanup in "$@"; do eval "$cleanup"; done' INT TERM EXIT

if test -f rescue-media.iso; then
    printf "rescue-media.iso exist\n" >&2
    exit 1
fi

WORKDIR=$(mktemp -d); set -- "rm -rf $WORKDIR" "$@"

CHROOT=$WORKDIR/chroot
ISO=$WORKDIR/iso

mkdir -p $CHROOT $ISO

mount -t tmpfs -o size=1024m tmpfs $ISO; set -- "umount $ISO" "$@"

mkdir -p $WORKDIR/base

mount -t tmpfs -o size=2048m tmpfs $WORKDIR/base; set -- "umount $WORKDIR/base" "$@"
mount -o bind $WORKDIR/base $CHROOT; set -- "umount $CHROOT" "$@"

debootstrap --arch=amd64 --components=main,restricted,multiverse,universe focal $CHROOT http://archive.ubuntu.com/ubuntu

mount -t proc proc $CHROOT/proc; set -- "umount $CHROOT/proc" "$@"
mount -t sysfs sys $CHROOT/sys; set -- "umount $CHROOT/sys" "$@"
mount -o bind /dev $CHROOT/dev; set -- "umount $CHROOT/dev" "$@"
mount -o bind /dev/pts $CHROOT/dev/pts; set -- "umount $CHROOT/dev/pts" "$@"

LC_ALL=C LANGUAGE=C LANG=C chroot $CHROOT sh <<'SHELL'
mkdir -p /var/lib/locales/supported.d
rm -rf /usr/lib/locale/* /var/lib/locales/supported.d/*

tee /var/lib/locales/supported.d/en >/dev/null <<'TEXT'
en_US.UTF-8 UTF-8
TEXT

tee /var/lib/locales/supported.d/pt >/dev/null <<'TEXT'
pt_PT.UTF-8 UTF-8
TEXT

locale-gen

tee /etc/default/locale >/dev/null <<'TEXT'
LANG=en_US.UTF-8
LANGUAGE=en
LC_CTYPE=pt_PT.UTF-8
LC_NUMERIC=pt_PT.UTF-8
LC_TIME=pt_PT.UTF-8
LC_COLLATE=pt_PT.UTF-8
LC_MONETARY=pt_PT.UTF-8
LC_MESSAGES=en_US.UTF-8
LC_PAPER=pt_PT.UTF-8
LC_NAME=pt_PT.UTF-8
LC_ADDRESS=pt_PT.UTF-8
LC_TELEPHONE=pt_PT.UTF-8
LC_MEASUREMENT=pt_PT.UTF-8
LC_IDENTIFICATION=pt_PT.UTF-8
TEXT

ln -sfn /usr/share/zoneinfo/Europe/Lisbon /etc/localtime
SHELL

chroot $CHROOT sh <<'SHELL'
. /etc/os-release

tee /etc/apt/sources.list >/dev/null <<TEXT
deb http://archive.ubuntu.com/ubuntu $VERSION_CODENAME main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu $VERSION_CODENAME-updates main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu $VERSION_CODENAME-security main restricted universe multiverse
deb http://archive.canonical.com/ubuntu $VERSION_CODENAME partner
TEXT

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-mark showmanual | grep -vE 'ubuntu-minimal' | xargs apt-mark auto
apt-get -y --purge autoremove
apt-get -y dist-upgrade
apt-get clean

apt-get -y install linux-generic-hwe-20.04-edge grub-pc-
apt-get clean

apt-get -y install grub-efi os-prober- grub-efi-amd64-signed-
apt-get clean

sed -Ei \
    -e 's/^#?(GRUB_CMDLINE_LINUX_DEFAULT=).*$/\1"net.ifnames=0 biosdevname=0 console=ttyS0 console=tty1"/' \
    -e 's/^#?(GRUB_TIMEOUT_STYLE=).*$/\1menu/' \
    -e 's/^#?(GRUB_TIMEOUT=).*$/\11/' \
    -e 's/^#?(GRUB_TERMINAL=).*$/\1console/' \
    -e 's/^#?(GRUB_DISABLE_RECOVERY=).*$/\1"true"/' \
    -e '$a\\nGRUB_DISABLE_OS_PROBER="true"' \
    /etc/default/grub

apt-get -y install ubuntu-standard gnupg patch apparmor- update-manager-core- ufw-
apt-get clean

apt-mark auto gnupg

patch -f /etc/bash.bashrc <<'PATCH'
@@ -32,13 +32,13 @@
 #esac

 # enable bash completion in interactive shells
-#if ! shopt -oq posix; then
-#  if [ -f /usr/share/bash-completion/bash_completion ]; then
-#    . /usr/share/bash-completion/bash_completion
-#  elif [ -f /etc/bash_completion ]; then
-#    . /etc/bash_completion
-#  fi
-#fi
+if ! shopt -oq posix; then
+  if [ -f /usr/share/bash-completion/bash_completion ]; then
+    . /usr/share/bash-completion/bash_completion
+  elif [ -f /etc/bash_completion ]; then
+    . /etc/bash_completion
+  fi
+fi

 # sudo hint
 if [ ! -e "$HOME/.sudo_as_admin_successful" ] && [ ! -e "$HOME/.hushlogin" ] ; then
PATCH

tee /etc/hostname >/dev/null <<'TEXT'
rescue
TEXT

tee /etc/hosts >/dev/null <<'TEXT'
127.0.0.1       localhost
127.0.1.1       rescue.media.intranet      rescue

# The following lines are desirable for IPv6 capable hosts
::1     localhost ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
TEXT

tee /etc/netplan/01-netcfg.yaml >/dev/null <<'YAML'
# This file describes the network interfaces available on your system
# For more information, see netplan(5).
network:
  version: 2
  renderer: networkd
  ethernets:
    eth0:
      dhcp4: true
YAML

apt-get -y install openssh-server
apt-get clean

rm /etc/ssh/ssh_host_*

find /var/log -type f -name '*.log' -print0 | xargs -0I% truncate -s0 "%"
find /var/lib/apt/lists -type f ! -name lock -print0 | xargs -0I% rm "%"
SHELL

eval "$1"; shift # /dev/pts
eval "$1"; shift # /dev
eval "$1"; shift # /sys
eval "$1"; shift # /proc
eval "$1"; shift # /chroot

mkdir -p $ISO/live

mksquashfs $WORKDIR/base $ISO/live/base.squashfs -noappend

eval "$1"; shift # /base

mount -t squashfs $ISO/live/base.squashfs $WORKDIR/base; set -- "umount $WORKDIR/base" "$@"

mkdir -p $WORKDIR/live

mount -t tmpfs -o size=1024m tmpfs $WORKDIR/live; set -- "umount $WORKDIR/live" "$@"

mkdir -p $WORKDIR/live/upperdir $WORKDIR/live/workdir

mount -t overlay -o lowerdir=$WORKDIR/base,upperdir=$WORKDIR/live/upperdir,workdir=$WORKDIR/live/workdir overlay $CHROOT; set -- "umount $CHROOT" "$@"
mount -t proc proc $CHROOT/proc; set -- "umount $CHROOT/proc" "$@"
mount -t sysfs sys $CHROOT/sys; set -- "umount $CHROOT/sys" "$@"
mount -o bind /dev $CHROOT/dev; set -- "umount $CHROOT/dev" "$@"
mount -o bind /dev/pts $CHROOT/dev/pts; set -- "umount $CHROOT/dev/pts" "$@"

chroot $CHROOT sh <<'SHELL'
export DEBIAN_FRONTEND=noninteractive

apt-get update

apt-get -y install live-boot systemd-sysv
apt-get clean

apt-get -y install kpartx f2fs-tools squashfs-tools mtools debootstrap qemu-utils jq socat isolinux xorriso
apt-get clean

mkdir -p /etc/systemd/system/getty@tty1.service.d

tee /etc/systemd/system/getty@tty1.service.d/override.conf >/dev/null <<'TEXT'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --noclear --autologin root %I $TERM
Type=idle
TEXT

ssh-keygen -A
sed -Ei 's/^#?(PermitRootLogin).*$/\1 yes/' /etc/ssh/sshd_config
printf 'media\nmedia' | passwd 2>/dev/null

tee /root/rescue.sh >/dev/null <<'SHELL_'
#!/bin/sh

printf "\nObtaining IP address\n"

while :; do
    IP="$(hostname -I)"
    if test -n "$IP"; then
        break
    fi
    sleep 1
done

printf '\nSSH User: root\nSSH Pass: media\nSSH Host: %s\n' "$IP"

TCP_SERVER="$(awk -v RS=' ' -F '=' '$1=="rescue.tcpserver"{print $2}' /proc/cmdline | tail -1)"
HOST="$(printf '%s' $TCP_SERVER | awk -F ':' '{print $1}')"
PORT="$(printf '%s' $TCP_SERVER | awk -F ':' '{print $2}')"

if test -n "$HOST" -a -n "$PORT"; then
    while :; do
        printf '\nExecuting shell script from tcp://%s\nUse: socat -u OPEN:script.sh TCP4-LISTEN:%s,reuseaddr\n\n' $TCP_SERVER $PORT
        socat -u "TCP4:$TCP_SERVER,forever" - | sh -
    done
fi
SHELL_

tee -a /root/.bashrc >/dev/null <<'SHELL_'

sh ~/rescue.sh
SHELL_

find /var/log -type f -name '*.log' -print0 | xargs -0I% truncate -s0 "%"
find /var/lib/apt/lists -type f ! -name lock -print0 | xargs -0I% rm "%"
SHELL

eval "$1"; shift # /dev/pts
eval "$1"; shift # /dev
eval "$1"; shift # /sys
eval "$1"; shift # /proc
eval "$1"; shift # /chroot

mksquashfs $WORKDIR/live/upperdir $ISO/live/live.squashfs -noappend

eval "$1"; shift # /live

mount -t squashfs $ISO/live/live.squashfs $WORKDIR/live; set -- "umount $WORKDIR/live" "$@"

mkdir -p $WORKDIR/tmp

mount -t tmpfs -o size=1024m tmpfs $WORKDIR/tmp; set -- "umount $WORKDIR/tmp" "$@"

mkdir -p $WORKDIR/tmp/upperdir $WORKDIR/tmp/workdir

mount -t overlay -o lowerdir=$WORKDIR/live:$WORKDIR/base,upperdir=$WORKDIR/tmp/upperdir,workdir=$WORKDIR/tmp/workdir overlay $CHROOT; set -- "umount $CHROOT" "$@"
mount -t proc proc $CHROOT/proc; set -- "umount $CHROOT/proc" "$@"
mount -t sysfs sys $CHROOT/sys; set -- "umount $CHROOT/sys" "$@"
mount -o bind /dev $CHROOT/dev; set -- "umount $CHROOT/dev" "$@"
mount -o bind /dev/pts $CHROOT/dev/pts; set -- "umount $CHROOT/dev/pts" "$@"

mkdir -p $CHROOT/iso
mount -o bind $ISO $CHROOT/iso; set -- "umount $CHROOT/iso" "$@"

chroot $CHROOT sh <<'SHELL'
mkdir -p /iso/boot/grub /iso/EFI/boot

cp /boot/initrd.img /iso/live/initrd
cp /boot/vmlinuz /iso/live/
cp -r /usr/lib/grub/x86_64-efi /iso/boot/grub/
cp -rT /usr/lib/syslinux/modules/bios /iso/isolinux
cp /usr/lib/ISOLINUX/isolinux.bin /iso/isolinux/
touch /iso/RESCUE_MEDIA

tee /grub-standalone.cfg >/dev/null <<'TEXT'
search --set=root --file /RESCUE_MEDIA
set prefix=($root)/boot/grub/
configfile /boot/grub/grub.cfg
TEXT

grub-mkstandalone --format=x86_64-efi --output=/bootx64.efi --locales="" --fonts="" boot/grub/grub.cfg=/grub-standalone.cfg
dd if=/dev/zero of=/iso/EFI/boot/efiboot.img bs=1M count=20
mkfs.vfat /iso/EFI/boot/efiboot.img
mmd -i /iso/EFI/boot/efiboot.img efi efi/boot
mcopy -vi /iso/EFI/boot/efiboot.img /bootx64.efi ::efi/boot/

tee /iso/isolinux/isolinux.cfg >/dev/null <<'TEXT'
UI menu.c32

MENU TITLE Rescue Media
DEFAULT linux
TIMEOUT 20

LABEL linux
  MENU LABEL Normal boot
  MENU DEFAULT
  KERNEL /live/vmlinuz
  APPEND initrd=/live/initrd boot=live net.ifnames=0 biosdevname=0 console=ttyS0 console=tty1 rescue.tcpserver=10.0.0.50:54321
TEXT

tee /iso/boot/grub/grub.cfg >/dev/null <<'TEXT'
search --set=root --file /RESCUE_MEDIA

set default=0
set timeout=2

menuentry "Normal boot" {
    linux ($root)/live/vmlinuz boot=live net.ifnames=0 biosdevname=0 console=ttyS0 console=tty1 rescue.tcpserver=10.0.0.50:54321
    initrd ($root)/live/initrd
}
TEXT

xorriso \
    -as mkisofs \
    -iso-level 3 \
    -o /rescue-media.iso \
    -full-iso9660-filenames \
    -volid "RESCUE_MEDIA" \
    -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin \
    -eltorito-boot \
        isolinux/isolinux.bin \
        -no-emul-boot \
        -boot-load-size 4 \
        -boot-info-table \
        --eltorito-catalog isolinux/isolinux.cat \
    -eltorito-alt-boot \
        -e /EFI/boot/efiboot.img \
        -no-emul-boot \
        -isohybrid-gpt-basdat \
    -append_partition 2 0xef /iso/EFI/boot/efiboot.img \
    /iso
SHELL

cp $CHROOT/rescue-media.iso ./
