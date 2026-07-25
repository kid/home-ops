# crs320 — ported verbatim from tf-stacks/prd/network/crs320/terragrunt.hcl.
# Single "base" stack, depends on rb5009's base stack.
{
  lib,
  tf,
  config,
  cidrLib,
  hcl,
  ...
}:
let
  environment = config.den.environments.prd;
  inherit (environment) networks;

  allVlanIds = lib.mapAttrsToList (_: net: net.vlanId) networks;

  routerosSecretsPath = hcl.raw ''"''${get_repo_root()}/secrets/${environment.name}/routeros.sops.yaml"'';

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
  };

  # Matches tf-catalog/modules/ros/base's `vlans` variable object shape
  # (name, vlan_id, mtu?, interface_lists?) — extra fields on
  # environment.networks entries (cidr, domain, …) are dropped anyway.
  toVlanInput =
    net:
    {
      inherit (net) name;
      vlan_id = net.vlanId;
    }
    // lib.optionalAttrs (net.mtu != null) { inherit (net) mtu; }
    // lib.optionalAttrs (net.interfaceLists != [ ]) { interface_lists = net.interfaceLists; };
in
{
  den.devices.crs320 = {
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

  tf.crs320 = {
    includes = [ tf.ros-base ];

    terragruntInputs = {
      base = {
        dependsOn = [ "rb5009" ];
        inputs = sharedInputs // {
          hostname = "crs320";
          routeros_endpoint = "10.99.0.2";
          routeros_secrets_path = routerosSecretsPath;

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
              comment = "pve0";
              untagged = networks.Talos.vlanId;
            };
            "sfp-sfpplus4" = {
              comment = "pve1";
              tagged = allVlanIds;
            };
            ether1 = {
              # NB: "command" is not a field tf-catalog/modules/ros/base's
              # ethernet_interfaces variable declares (it wants "comment") —
              # ported verbatim from the hand-written leaf, flagged to the
              # user rather than silently fixed.
              command = "vulkan";
              untagged = networks.Trusted.vlanId;
              tagged = [
                networks.Management.vlanId
                networks.Talos.vlanId
                networks.RosLab.vlanId
                networks.LabTalos.vlanId
                networks.LabTalosSvc.vlanId
                networks.LabTrusted.vlanId
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
              comment = "pve0-ipmi";
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
            Management = "${cidrLib.cidrhost networks.Management.cidr 2}/${toString networks.Management.prefix}";
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
