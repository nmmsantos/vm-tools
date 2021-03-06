#!/bin/sh

export DEBIAN_FRONTEND=noninteractive

if dpkg -s grub-efi >/dev/null 2>&1; then
    echo "Nothing to do"
    exit 0
fi

tee /etc/fstab >/dev/null <<EOF
# <file system>                            <mount point>  <type>  <options>              <dump>  <pass>
UUID=$EFI_PART_UUID                             /boot/efi      vfat    dmask=0022,fmask=0133  0       2
UUID=$ROOT_PART_UUID  /              ext4    errors=remount-ro      0       1
EOF

apt-get -y install grub-efi os-prober- grub-efi-amd64-signed-

sed -Ei \
    -e 's/^#?(GRUB_CMDLINE_LINUX_DEFAULT=).*$/\1"net.ifnames=0 biosdevname=0 console=ttyS0"/' \
    -e 's/^#?(GRUB_TIMEOUT_STYLE=).*$/\1menu/' \
    -e 's/^#?(GRUB_TIMEOUT=).*$/\11/' \
    -e 's/^#?(GRUB_TERMINAL=).*$/\1console/' \
    -e 's/^#?(GRUB_DISABLE_RECOVERY=).*$/\1"true"/' \
    -e '$a\\nGRUB_DISABLE_OS_PROBER="true"' \
    /etc/default/grub

update-grub
grub-install --removable $VHDD_LOOP
grub-install --removable --recheck $VHDD_LOOP
