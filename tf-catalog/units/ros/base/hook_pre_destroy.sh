#!/usr/bin/env bash

set -euo pipefail

if tofu state list | grep -q 'routeros_ip_address'; then
  tofu state rm routeros_ip_address.oob
fi

