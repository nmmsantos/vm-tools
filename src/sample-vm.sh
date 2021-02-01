#!/bin/sh

exec ./easy-qemu-system-x86_64.py \
    -name salt-master \
    -bios /usr/share/ovmf/OVMF.fd \
    -m 2048 \
    {defaults} \
    {cpu,2} \
    {hdd,{snap,salt-master.qcow2}} \
    {net,192.168.5.1/24} \
    {serial} \
    {monitor} \
    {video,virtio}
