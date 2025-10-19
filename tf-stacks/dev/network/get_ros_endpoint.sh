#!/usr/bin/env bash

set -euo pipefail

ip_address="$1"

if nc -zv "${ip_address}" 443 &>/dev/null; then
  echo -n "https://${ip_address}"
else
  echo -n "http://${ip_address}"
fi
