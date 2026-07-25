# Network entity schema and instance registry.
#
# One entry per item in tf-stacks/prd/env.hcl's `vlans_array`. A network is
# declared like a device (den.networks.<name> = { environment = "prd"; vlanId
# = ...; }) and fanned into its environment's scope by
# den.policies.env-to-networks (modules/den/policies/fleet.nix) — the same
# den.lib.policy.instantiate + resolve.to "network" mechanism any entity's
# aspect content can call, so a future cluster entity could contribute its
# own VLAN into an environment without a hand edit here (mirrors nixopslab's
# cluster-collect-k3s-nodes pipe collecting host data up into cluster scope).
#
# This registry only holds the *declared* fields — cidr/prefix computation
# from environment.cidrBase happens downstream, in env-to-networks, once a
# network is actually resolved against its environment (a network doesn't
# have a live handle to its environment entity at registry-definition time).
{ lib, tf, ... }:
{
  config.den.schema.network.isEntity = true;

  options.den.networks = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule (
        { name, ... }:
        {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              default = name;
              description = "Network (VLAN) name";
            };

            environment = lib.mkOption {
              type = lib.types.str;
              description = "Name of the den.environments entry this network belongs to";
            };

            vlanId = lib.mkOption {
              type = lib.types.ints.u16;
              description = "802.1Q VLAN ID";
            };

            prefix = lib.mkOption {
              type = lib.types.ints.between 0 32;
              default = 24;
              description = "Subnet prefix length carved out of the environment's cidrBase";
            };

            domain = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "DNS domain for this network, e.g. \${name}.\${environment.domain}";
            };

            interfaceLists = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "RouterOS interface lists this network's members belong to";
            };

            routed = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Whether this VLAN gets an L3 gateway/cidr at all (false for lab-only L2 VLANs)";
            };

            dhcp = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Whether rb5009 runs a DHCP server for this VLAN";
            };

            mtu = lib.mkOption {
              type = lib.types.nullOr lib.types.ints.positive;
              default = null;
              description = "Bridge VLAN MTU override";
            };

            cidr = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Explicit CIDR override — skips the environment.cidrBase/vlanId computation";
            };

            dhcpGateway = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "DHCP gateway override (defaults to the network's own .1 address)";
            };

            dhcpDnsServers = lib.mkOption {
              type = lib.types.nullOr (lib.types.listOf lib.types.str);
              default = null;
              description = "DHCP DNS servers override (defaults to the network's own .1 address)";
            };

            dhcpNtpServers = lib.mkOption {
              type = lib.types.nullOr (lib.types.listOf lib.types.str);
              default = null;
              description = "DHCP NTP servers override (defaults to the network's own .1 address)";
            };

            aspect = lib.mkOption {
              type = lib.types.raw;
              default = tf.${name} or { };
              defaultText = "tf.<name>";
              description = "Aspect that configures this network";
            };
          };
        }
      )
    );
    default = { };
    description = "Network (VLAN) entity registry for den";
  };
}
