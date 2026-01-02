#!/usr/bin/env bash

source_image="$1"

qemu-img convert -f raw -O qcow2 "${source_image}" "rootfs.img"
tar --zstd -cf ./chr.tar.zst metadata.yaml rootfs.img
incus image import --alias mikrotik/chr chr.tar.zst
incus launch mikrotik/chr -c security.secureboot=false --console
