destroy:
  #!/usr/bin/env bash
  terragrunt --working-dir tf-stacks/dev run --all --queue-exclude-dir lab -- destroy
  regex="proxmox_virtual_environment_vm.devices|terraform_data.initial_provisioning"
  for item in $(terragrunt --working-dir tf-stacks/dev/lab state list); do
    if [[ $item  =~ $regex ]]; then
      terragrunt --working-dir tf-stacks/dev/lab run taint $item
    fi
  done

apply-all:
  terragrunt --working-dir tf-stacks/dev run --all -- apply

apply:
  terragrunt --working-dir tf-stacks/dev run --all --queue-exclude-dir lab -- apply
    

[working-directory: 'test']
test:
  go test -v
