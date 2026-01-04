terragrunt_args := "--non-interactive"

# Displayt he available commands
default:
  just --list

# Run the given command against the lab stack
lab *command:
  terragrunt {{terragrunt_args}} --working-dir "tf-stacks/dev" run --all --queue-include-dir "lab" -- {{command}}

# Run the given command against the all the network stacks
network command *flags:
  terragrunt {{terragrunt_args}} --working-dir "tf-stacks/dev" run --all --queue-exclude-dir "lab" {{flags}} -- {{command}}

# Deoploy the lab and run bootstrap the network stack
bootstrap: (lab "apply")
  #!/usr/bin/env bash
  set -euo pipefail
  export TF_VAR_routeros_username=admin
  export TF_VAR_routeros_password=admin
  just network apply

# Reset network state then mark VMs for recreation
lab-reset: clear-network-state
  #!/usr/bin/env bash
  set -euo pipefail
  regex="proxmox_virtual_environment_vm.devices|routeros_ip_dhcp_server_lease.leases"
  for item in $(terragrunt --working-dir tf-stacks/dev/lab state list); do
    if [[ $item  =~ $regex ]]; then
      terragrunt --working-dir tf-stacks/dev/lab run taint $item
    fi
  done

clear-stack-state stack:
  #!/usr/bin/env bash
  set -euo pipefail
  mapfile -t items < <(terragrunt --working-dir "tf-stacks/{{stack}}" state list)
  if [[ ${#items[@]} -gt 0 ]]; then
    terragrunt --working-dir "tf-stacks/{{stack}}" state rm "${items[@]}"
  fi

# Reset the terraform state on all network stacks
clear-network-state:
  #!/usr/bin/env bash
  set -euo pipefail
  for stack in $(terragrunt --working-dir "tf-stacks/dev/network" list); do
    mapfile -t items < <(terragrunt --working-dir "tf-stacks/dev/network/$stack" state list)
    if [[ ${#items[@]} -gt 0 ]]; then
      terragrunt --working-dir "tf-stacks/dev/network/$stack" state rm "${items[@]}"
    fi
  done

# Prepare all stacks for local development
develop:
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

test:
  cd test && go test -v
