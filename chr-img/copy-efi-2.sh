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

(
echo 2 # use GPT
echo x # extra functionality
echo e # relocate backup data structures to the end of the disk
echo r # Recovery/transformation
echo f # load MBR and build fresh GPT from it
echo y # Warning! This will destroy the currently defined partitions! Proceed? (Y/N):
echo x # extra functionality
echo a # set attributes
echo 1 #  Partition number (1-2):
echo 2 # Toggle which attribute field (0-63, 64 or <Enter> to exit):
echo   # Toggle which attribute field (0-63, 64 or <Enter> to exit):
echo m # return to main menu
echo t # change partition code
echo 1 # select first partition
echo EF00 # Hex code or GUID (L to show codes, Enter = EF00):
echo c # change a partition's name
echo 1 #  Partition number (1-2):
echo RouterOS Boot # Enter name:
echo c # change a partition's name
echo 2 #  Partition number (1-2):
echo RouterOS # Enter name:
echo x # extra functionality
echo r # Recovery/transformation
echo h # Hybrid MBR
echo 1 2 # partitions added to the hybrid MBR
echo n # Place EFI GPT (0xEE) partition first in MBR (good for GRUB)? (Y/N)
echo 83 # Enter an MBR hex code (default 83)
echo y # Set the bootable flag? (Y/N)
echo 83 # Enter an MBR hex code (default 83)
echo n # Set the bootable flag? (Y/N)
echo n # Unused partition space(s) found. Use one to protect more partitions? (Y/N)
echo w # write changes to disk
echo y # confirm
) | sudo -E gdisk /dev/nbd1

sudo -E qemu-nbd -d /dev/nbd0

sudo -E sgdisk -v /dev/nbd1

sudo -E qemu-nbd -d /dev/nbd0
sudo -E qemu-nbd -d /dev/nbd1

qemu-system-x86_64-uefi -enable-kvm -cpu host -m 1024 -drive file="$target_image",if=virtio -nographic

