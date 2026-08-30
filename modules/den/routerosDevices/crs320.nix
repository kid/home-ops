# crs320's Terragrunt stack input. Single "base" stack, depends on rb5009's
# base stack.
{
  lib,
  den,
  config,
  ...
}:
let
  rosLib = import ../../network/_ros-lib.nix { inherit lib; };
  inherit (rosLib) toVlanInput sharedInputs;

  environment = config.den.environments.prd;
  inherit (environment) networks;

  allVlanIds = rosLib.allVlanIds networks;

  managementHostNum = 2;
  managementMac = "f4:1e:57:d1:75:94";
in
{
  den.routerosDevices.crs320 = {
    environment = "prd";
    hostname = "crs320";
    routerosEndpoint = "10.99.0.2";
    certificateAltNames = [
      "DNS:crs320"
      "DNS:crs320.kidibox.net"
      "IP:10.99.0.2"
      "IP:192.168.88.1"
    ];
  };

  # crs320's own entry in the network client-device registry — its
  # Management-VLAN address/MAC, the single source of truth other
  # routerosDevices/aspects reference (e.g. rb5009's dhcp_static_leases/
  # firewall-rule entries for crs320, via config.den.devices.crs320).
  den.devices.crs320 = {
    network = "Management";
    hostNum = managementHostNum;
    mac = managementMac;
  };

  den.aspects.crs320 = {
    includes = [ den.aspects.routeros.base ];

    terragruntInputs = {
      base = {
        dependsOn = [ "rb5009" ];
        inputs = sharedInputs // {
          hostname = "crs320";

          op_item_routeros = "CRS320 - user - kid";

          routeros_endpoint = "10.99.0.2";

          # routeros_groups/routeros_users are contributed centrally by
          # modules/network/aspects/ros-base.nix, sourced from
          # den.users.registry/den.groups — not hand-written per device
          # anymore. Per-user passwords still come from 1Password: admin
          # reuses op_item_routeros above, every other user needs an item
          # titled "CRS320 - user - <username>" in vault op_vault.
          # DO NOT apply with the still-TODO registry group/user data, it
          # will destroy the users/groups/ssh keys currently on the router.

          certificate_alt_names = [
            "DNS:crs320"
            "DNS:crs320.kidibox.net"
            "IP:10.99.0.2"
            "IP:192.168.88.1"
          ];

          vlans = {
            Management = toVlanInput networks.Management;
          };

          ethernet_interfaces = {
            "sfp-sfpplus1" = {
              comment = "uplink to rb5009";
              tagged = allVlanIds;
            };
            "sfp-sfpplus3" = {
              comment = "node1";
              untagged = networks.Servers.vlanId;
              tagged = lib.sort (a: b: a < b) [
                networks.Storage.vlanId
                networks.K3s.vlanId
              ];
            };
            "sfp-sfpplus4" = {
              comment = "pve1";
              tagged = allVlanIds;
            };
            ether1 = {
              # NB: "command" is not a field terragrunt-infra-catalog's ros-base
              # module ethernet_interfaces variable declares (it wants "comment")
              # — the module silently ignores it. Intentional, not a bug to fix.
              command = "vulkan";
              untagged = networks.Trusted.vlanId;
              tagged = lib.sort (a: b: a < b) [
                networks.Management.vlanId
                networks.K3s.vlanId
              ];
            };
            ether2 = {
              comment = "rb5009";
              untagged = networks.Management.vlanId;
            };
            ether7 = {
              comment = "capxr1";
              tagged = allVlanIds;
            };
            ether9 = {
              comment = "capxr0";
              tagged = allVlanIds;
            };
            ether10 = {
              comment = "doorbell";
              untagged = networks.IotLocal.vlanId;
            };
            ether11 = {
              comment = "petdoor";
              untagged = networks.IotInternet.vlanId;
            };
            ether14 = {
              comment = "node1-ipmi";
              untagged = networks.Management.vlanId;
            };
            ether16 = {
              comment = "pve1-ipmi";
              untagged = networks.Management.vlanId;
            };
            ether17 = {
              comment = "oob";
              bridge_port = false;
              interface_lists = [ "MANAGEMENT" ];
            };
          };

          ip_addresses = {
            ether17 = "192.168.88.1/24";
            Management = "${config.den.devices.crs320.address}/${toString networks.Management.prefix}";
          };

          dhcp_servers = {
            ether17 = {
              cidr = "192.168.88.0/24";
              dns_servers = [ ];
            };
          };
        };
      };
    };
  };
}
