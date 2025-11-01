#!/usr/bin/env bash

set -euo pipefail

if tofu state list | grep -q 'routeros_ip_address.oob'; then
  tofu state rm routeros_ip_address.oob
fi

