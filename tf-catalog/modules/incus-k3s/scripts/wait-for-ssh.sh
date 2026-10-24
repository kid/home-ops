#!/usr/bin/env bash
# Waits up to 10 minutes for SSH on a freshly booted base image.
set -euo pipefail

target="$1"
for _ in $(seq 120); do
  if ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null "${target}" true 2>/dev/null; then
    exit 0
  fi
  sleep 5
done
echo "no SSH on ${target} after 10 minutes" >&2
exit 1
