#!/bin/sh

set -e

TRUENAS_IP=10.0.0.61

if test -d k3os -o -f k3os.iso; then
    printf "%s\n" "k3os or k3os.iso exist" >&2
    exit 1
fi

mkdir -p k3os/mount
mkdir -p k3os/iso/boot/grub

curl -fsSLo k3os/k3os.iso https://github.com/rancher/k3os/releases/download/v0.20.7-k3s1r0/k3os-amd64.iso

mount -o loop k3os/k3os.iso k3os/mount
cp -r k3os/mount/k3os k3os/iso/

sed -E \
    -e 's|(set default=)[0-9]+|\11|' \
    -e 's|(set timeout=)[0-9]+|\13|' \
    -e 's|(k3os.mode=install)|\1 k3os.install.silent=true k3os.install.device=/dev/vda k3os.install.config_url=http://'$TRUENAS_IP':54321/config.yaml k3os.install.tty=ttyS0 k3os.install.power_off=true|' \
    k3os/mount/boot/grub/grub.cfg \
    >k3os/iso/boot/grub/grub.cfg

umount k3os/mount

grub-mkrescue -o k3os.iso k3os/iso/ -- -volid K3OS

rm -rf k3os
