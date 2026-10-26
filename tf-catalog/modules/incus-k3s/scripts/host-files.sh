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

# sops-nix decrypts with this key, as the .age-pub recipient in .sops.yaml.
pub="$(ssh-keygen -y -f etc/ssh/ssh_host_ed25519_key | cut -d' ' -f1-2)"
if [[ "${pub}" != "$(cut -d' ' -f1-2 etc/ssh/ssh_host_ed25519_key.pub)" ]]; then
  echo "${HOST}: private key does not match ssh_host_ed25519_key.pub" >&2
  exit 1
fi
if [[ "$(ssh-to-age <<<"${pub}")" != "$(cat "${host_dir}/ssh_host_ed25519_key.age-pub")" ]]; then
  echo "${HOST}: key does not match ssh_host_ed25519_key.age-pub" >&2
  exit 1
fi
