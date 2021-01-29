#!/bin/sh

export DEBIAN_FRONTEND=noninteractive

ENV=/boot/efi/vm-bootstrap.env

if test -f $ENV -a -r $ENV; then
    . $ENV
    rm $ENV
fi

unset ENV

# resize root partition
sync; echo "- +" | sfdisk -f --no-reread $(lsblk -lnpo PKNAME,MOUNTPOINT | awk '$2=="/" {print $1}') -N 2
sync; partprobe
sync; resize2fs $(lsblk -lnpo PATH,MOUNTPOINT | awk '$2=="/" {print $1}')
sync
