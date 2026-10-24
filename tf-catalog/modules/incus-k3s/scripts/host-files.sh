#!/usr/bin/env bash
# nixos-anywhere extra_files_script: runs in the directory that becomes the
# installed system's /, with HOST and REPO_ROOT from the install module.
set -euo pipefail

host_dir="${REPO_ROOT}/secrets/hosts/${HOST}"

install -d -m 755 etc/ssh
umask 0177
sops --decrypt --input-type binary --output-type binary \
  "${host_dir}/ssh_host_ed25519_key.sops" > etc/ssh/ssh_host_ed25519_key
umask 0133
cp "${host_dir}/ssh_host_ed25519_key.pub" etc/ssh/ssh_host_ed25519_key.pub
