#!/usr/bin/env bash
# Terraform "external" data source protocol: reads a JSON query object on
# stdin ({"attr": "<nixosConfigurations attr name>"}), writes a flat JSON
# result object to stdout ({"qcow2": "...", "metadata": "..."}).
set -euo pipefail

query="$(cat)"
attr="$(jq -r '.attr' <<<"${query}")"

repo_root="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
flake_ref="${repo_root}#nixosConfigurations.${attr}.config.system.build"

qcow2_out="$(nix build --print-out-paths --no-link "${flake_ref}.qemuImage")"
metadata_out="$(nix build --print-out-paths --no-link "${flake_ref}.metadata")"

qcow2="${qcow2_out}/nixos.qcow2"
# Filename is version-stamped (nixos-image-lxc-metadata-<version>-<system>.tar.xz) — glob for it.
metadata="$(find "${metadata_out}/tarball" -name '*.tar.xz' -print -quit)"

jq -n --arg qcow2 "${qcow2}" --arg metadata "${metadata}" '{qcow2: $qcow2, metadata: $metadata}'
