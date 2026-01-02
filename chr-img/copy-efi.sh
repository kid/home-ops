#!/usr/bin/env bash

set -euo pipefail

source_image="$1"
target_image="${source_image%.img}-efi.raw"

cp "$source_image" "$target_image"

sudo -E qemu-nbd -d /dev/nbd0
sudo -E qemu-nbd -d /dev/nbd1

# qemu-img create -f raw "$target_image" 128M

sudo -E qemu-nbd -c /dev/nbd0 -f raw "$source_image"
sudo -E qemu-nbd -c /dev/nbd1 -f raw "$target_image"

sleep 1

sudo -E mkfs.vfat -F16 /dev/nbd1p1

sudo -E rm -rf /tmp/chr
sudo -E mkdir -p /tmp/chr/{source,target}/{part1,part2}

sudo -E mount /dev/nbd0p1 /tmp/chr/source/part1
sudo -E mount /dev/nbd1p1 /tmp/chr/target/part1

sudo -E rsync -a /tmp/chr/source/part1/ /tmp/chr/target/part1/

sudo -E umount /tmp/chr/{source,target}/part1
sudo -E rm -rf /tmp/chr*

sudo -E sgdisk -v /dev/nbd1

sudo -E qemu-nbd -d /dev/nbd0
sudo -E qemu-nbd -d /dev/nbd1

qemu-system-x86_64-uefi -enable-kvm -cpu host -m 1024 -drive file="$target_image",if=virtio -nographic

