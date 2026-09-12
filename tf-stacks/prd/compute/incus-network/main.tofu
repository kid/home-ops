# No incus provider resource here, unlike ../../dev/compute/incus-network:
# the K3s VLAN bridge (`k3s-br0`) is created by NixOS on node1
# (modules/den/hosts/node1.nix), not by Incus/Terraform. Incus's `physical`
# network type doesn't yet support multiple instances against a bridge
# parent (lxc/incus#1735), so a Terraform-managed Incus network isn't an
# option here — this unit only tracks the bridge's name as an output, so
# ../incus-k3s can depend on it the same way dev's stack depends on its
# own incus-network unit.

output "network_name" {
  value = "k3s-br0"
}
