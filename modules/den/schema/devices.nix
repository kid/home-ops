# Network client-device registry — a Proxmox host, a camera, a vacuum robot,
# ... anything with a known MAC/host-number/VLAN, used to derive
# `dhcp_static_leases` dynamically (modules/network/_ros-lib.nix's
# `staticLeasesByNetwork`, wired in modules/den/routerosDevices/rb5009.nix).
#
# Deliberately flat/non-entity — no isEntity, no resolve.to/scope-tree walk
# — same reasoning already established for den.users.registry (see
# AGENTS.md's "Users" section): a single registry, read directly by a single
# consumer, no "many decoupled producers" problem to solve.
#
# Not to be confused with `den.routerosDevices` (modules/den/schema/
# routerosDevices.nix) — the RouterOS boxes (rb5009, crs320) themselves,
# a real scope-tree entity kind with its own Terraform/Terragrunt stacks.
{
  lib,
  config,
  ...
}:
let
  # `config` inside the submodule below is that device's own resolved config
  # (shadowing this one) — capture the flake-root config here so `address`'s
  # `default` can still reach den.networks/den.environments, same pattern
  # modules/den/schema/environments.nix uses for its own computed `networks`
  # field.
  rootConfig = config;
in
{
  options.den.devices = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule (
        { name, config, ... }:
        {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              default = name;
              description = "Device name";
            };

            network = lib.mkOption {
              type = lib.types.str;
              description = "Name of the den.networks entry this device is on";
            };

            hostNum = lib.mkOption {
              type = lib.types.ints.unsigned;
              description = "Host number within the network's CIDR (can be an arbitrary computed expression, e.g. for a device whose address encodes a different VLAN's numbering scheme)";
            };

            mac = lib.mkOption {
              type = lib.types.str;
              description = "MAC address";
            };

            # Resolved directly here (not left to every consumer to redo
            # network.methods.host themselves) — consumers just read
            # config.den.devices.<name>.address.
            address = lib.mkOption {
              type = lib.types.str;
              default =
                let
                  networkCfg = rootConfig.den.networks.${config.network};
                  envNetworks = rootConfig.den.environments.${networkCfg.environment}.networks;
                in
                envNetworks.${config.network}.methods.host config.hostNum;
              defaultText = "<network's resolved methods.host> hostNum";
              description = "Resolved IP address (network.cidr host'd at hostNum)";
            };
          };
        }
      )
    );
    default = { };
    description = "Network client device registry (hostname/MAC/host-number/VLAN) — used to derive dhcp_static_leases";
  };
}
