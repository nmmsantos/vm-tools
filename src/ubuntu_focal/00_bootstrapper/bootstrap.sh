#!/bin/sh

set -x

export DEBIAN_FRONTEND=noninteractive

ENV="$(dirname "$(readlink -f "$0")")/vm-bootstrap.env"

if test -f "$ENV" -a -r "$ENV"; then
    . "$ENV"
fi

unset ENV

# resize root partition
sync; echo "- +" | sfdisk -f --no-reread $(lsblk -lnpo PKNAME,MOUNTPOINT | awk '$2=="/" {print $1}') -N 2
sync; partprobe
sync; resize2fs $(lsblk -lnpo PATH,MOUNTPOINT | awk '$2=="/" {print $1}')
sync
