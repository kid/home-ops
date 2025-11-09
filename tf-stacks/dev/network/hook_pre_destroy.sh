#!/usr/bin/env bash

set -euo pipefail

if tofu state list | grep -q 'routeros_ip_address.ethernet["ether1"]'; then
  tofu state rm 'routeros_ip_address.ethernet["ether1"]'
fi

