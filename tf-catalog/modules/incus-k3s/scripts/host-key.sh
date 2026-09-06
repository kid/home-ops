#!/usr/bin/env bash
# Terraform "external" data source protocol: reads a JSON query object on
# stdin ({"host": "<den.hosts entity name>"}), writes a flat JSON result
# object to stdout ({"private": "...", "public": "..."}).
set -euo pipefail

query="$(cat)"
host="$(jq -r '.host' <<<"${query}")"

repo_root="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
sops_file="${repo_root}/secrets/hosts/${host}/ssh_host_ed25519_key.sops"
pub_file="${repo_root}/secrets/hosts/${host}/ssh_host_ed25519_key.pub"

if [[ ! -f "${sops_file}" ]]; then
  (cd "${repo_root}" && nix run .#provision-host-key -- "${host}" 1>&2)
fi

private="$(sops --decrypt --input-type binary --output-type binary "${sops_file}")"
public="$(cat "${pub_file}")"

jq -n --arg private "${private}" --arg public "${public}" '{private: $private, public: $public}'
