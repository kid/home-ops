#!/usr/bin/env bash

set -euo pipefail

# Read input JSON (from OpenTofu)
# eval "$(jq -r '@sh "endpoint=\(.ENDPOINT)"')"
ENDPOINT="$1"

# If ENDPOINT already includes a scheme (e.g., http:// or https://), return it as-is
if [[ "$ENDPOINT" =~ ^[a-zA-Z][a-zA-Z0-9+.-]*:// ]]; then
  echo "{\"endpoint\": \"$ENDPOINT\"}"
  exit 0
fi

if nc -zv "$ENDPOINT" 443; then
  echo "{\"endpoint\": \"https://$ENDPOINT\"}"
else
  echo "{\"endpoint\": \"http://$ENDPOINT\"}"
fi
