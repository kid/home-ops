#!/usr/bin/env bash
# Terraform "external" data source protocol: writes {"path": "<repo root>"}.
# Terragrunt runs the module from a cache directory inside the checkout.
set -euo pipefail

jq -n --arg path "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)" '{path: $path}'
