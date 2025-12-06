default:
  just --list

destroy:
  #!/usr/bin/env bash
  set -euo pipefail
  terragrunt --working-dir tf-stacks/dev run --all --queue-exclude-dir lab -- destroy
  regex="proxmox_virtual_environment_vm.devices|routeros_ip_dhcp_server_lease.leases"
  for item in $(terragrunt --working-dir tf-stacks/dev/lab state list); do
    if [[ $item  =~ $regex ]]; then
      terragrunt --working-dir tf-stacks/dev/lab run taint $item
    fi
  done

destroy-all:
  terragrunt --working-dir tf-stacks/dev run --all -- destroy

apply-all:
  terragrunt --working-dir tf-stacks/dev run --all -- apply

apply:
  terragrunt --working-dir tf-stacks/dev run --all --queue-exclude-dir lab -- apply

[working-directory: 'test']
test:
  go test -v

init-dev:
  #!/usr/bin/env bash
  set -euo pipefail
  ROOT_DIR="tf-catalog/modules"
  # Iterate through likely module directories (two and three levels deep)
  for dir in $(ls -d "$ROOT_DIR"/* "$ROOT_DIR"/*/* 2>/dev/null); do
    base="$(basename "$dir")"
    # Skip directories starting with '_'
    if [[ "$base" == _* ]]; then
      continue
    fi
    if ls "$dir"/*.tofu >/dev/null 2>&1; then
      echo "Initializing tofu module in: $dir"
      (cd "$dir" && tofu init -upgrade)
    fi
  done
