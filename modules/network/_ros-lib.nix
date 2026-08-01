# Helpers shared between modules/devices/{rb5009,crs320}.nix — previously
# duplicated byte-for-byte in both files. Leading underscore: import-tree
# (the mechanism that auto-imports everything under modules/ as a
# flake-parts module) skips any path containing `/_` by design, so this is
# an ordinary Nix file, imported directly, not a dendritic module.
{ lib, cidrLib }:
{
  allVlanIds = networks: lib.sort (a: b: a < b) (lib.mapAttrsToList (_: net: net.vlanId) networks);

  # Matches terragrunt-infra-catalog's ros-base module `vlans` variable
  # object shape (name, vlan_id, mtu?, interface_lists?).
  toVlanInput =
    net:
    {
      inherit (net) name;
      vlan_id = net.vlanId;
    }
    // lib.optionalAttrs (net.mtu != null) { inherit (net) mtu; }
    // lib.optionalAttrs (net.interfaceLists != [ ]) { interface_lists = net.interfaceLists; };

  # terragrunt-infra-catalog's ros-firewall module `vlans` variable — address
  # is the router's own IP on this VLAN (host 1, same as rb5009.nix's own
  # ip_addresses), used to scope firewall's per-VLAN self-access rules
  # instead of querying the live device for it.
  toFirewallVlanInput = net: {
    inherit (net) name;
    vlan_id = net.vlanId;
    address = cidrLib.cidrhost net.cidr 1;
  };

  # tf-stacks/prd/network/base.hcl's `shared_inputs` — merged into every prd
  # network leaf via root.hcl's `base_inputs`, not just ros/base's own
  # variables (Terraform just warns and ignores values for variables a
  # module doesn't declare).
  sharedInputs = {
    bridge_name = "bridge1";
    dns_upstream_servers = [
      "9.9.9.9"
      "149.112.112.112"
    ];
    mgmt_interface_list = "MANAGEMENT";
    wan_interface_list = "WAN";
    op_vault = "home-ops";
  };
}
