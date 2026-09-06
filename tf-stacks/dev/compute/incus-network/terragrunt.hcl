# No `terraform.source`: this directory's own main.tofu is the module, run
# in place. dev-only — prd's k3s1 uses node1's NixOS-managed K3s-VLAN
# bridge instead of a Terraform-managed one.
include "root" {
  path = find_in_parent_folders("root.hcl")
}
