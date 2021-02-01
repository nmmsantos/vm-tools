#!/bin/sh

exec ../easy-qemu-system-x86_64.py \
    -name app-server \
    -bios /usr/share/ovmf/OVMF.fd \
    -m 2048 \
    {defaults} \
    {cpu,2} \
    {hdd,{snap,app-server.qcow2}} \
    {net,192.168.5.1/24} \
    {serial} \
    {monitor} \
    {video,qxl}
