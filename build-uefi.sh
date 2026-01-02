#!/usr/bin/env bash

set -euo pipefail

source_image="$1"
target_image="${source_image%.img}-efi.raw"

qemu-img create -f raw "$target_image" 128M

sgdisk -n 1:2048:+32M -t 1:ef00 -c 1:"RooterOS Boot"  "$target_image"
sgdisk -n 2:0:-1M     -t 2:8300 -c 2:"RooterOS"       "$target_image"

sudo -E qemu-nbd -c /dev/nbd0 -f raw "$source_image"
sudo -E qemu-nbd -c /dev/nbd1 -f raw "$target_image"

sleep 1

sudo -E mkfs.vfat /dev/nbd1p1
sudo -E mkfs.ext3 /dev/nbd1p2

sudo -E rm -rf /tmp/chr
sudo -E mkdir -p /tmp/chr/{source,target}/{part1,part2}

sudo -E mount /dev/nbd0p1 /tmp/chr/source/part1
sudo -E mount /dev/nbd0p2 /tmp/chr/source/part2
sudo -E mount /dev/nbd1p1 /tmp/chr/target/part1
sudo -E mount /dev/nbd1p2 /tmp/chr/target/part2

sudo -E rsync -a /tmp/chr/source/part1/ /tmp/chr/target/part1/
sudo -E rsync -a /tmp/chr/source/part2/ /tmp/chr/target/part2/


sudo -E umount /tmp/chr/{source,target}/{part1,part2}
sudo -E rm -rf /tmp/chr*

sudo -E qemu-nbd -d /dev/nbd0
sudo -E qemu-nbd -d /dev/nbd1

qemu-img convert -f raw -O qcow2 "${target_image}" "rootfs.img"

tar --zstd -cf ./chr.tar.zst metadata.yaml rootfs.img
incus image import --alias mikrotik/chr chr.tar.zst
