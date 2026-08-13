# rb5009's Terragrunt stack inputs (base/capsman/dns/firewall/qos).
#
# Two intentional quirks, not bugs to fix:
#   - qos has no `dependencies` block, unlike its capsman/dns/firewall
#     siblings (all of which depend on this device's own base stack).
#   - the original firewall leaf's `vlans_forward_rules` HCL object literal
#     defines the "Media" key twice; HCL's object-constructor semantics keep
#     only the *last* occurrence (first is fully dead). Nix attrsets can't
#     even represent a literal duplicate key, so this file only encodes the
#     winning (second) value — same observable result, not a fix.
{
  lib,
  den,
  config,
  cidrLib,
  ...
}:
let
  rosLib = import ../network/_ros-lib.nix { inherit lib cidrLib; };
  inherit (rosLib)
    toVlanInput
    toFirewallVlanInput
    sharedInputs
    staticLeasesByNetwork
    ;

  environment = config.den.environments.prd;
  inherit (environment) networks;

  allVlanIds = rosLib.allVlanIds networks;
  routedNetworks = lib.filterAttrs (_: net: net.routed) networks;

  # Every ros-* stack needs its own onepassword provider auth — the routeros
  # provider connects as whichever fleet user op_item_routeros names
  # (currently kid, not admin; vault "home-ops", mirrors the K8s
  # ClusterSecretStore convention).
  commonInputs = {
    hostname = "rb5009";
    op_item_routeros = "RB5009 - user - kid";
  };

  cidrHostPrefixed = net: hostnum: "${cidrLib.cidrhost net.cidr hostnum}/${toString net.prefix}";

  gatewayFor = net: if net.dhcpGateway != null then net.dhcpGateway else cidrLib.cidrhost net.cidr 1;
  dnsServersFor =
    net: if net.dhcpDnsServers != null then net.dhcpDnsServers else [ (cidrLib.cidrhost net.cidr 1) ];
  ntpServersFor =
    net: if net.dhcpNtpServers != null then net.dhcpNtpServers else [ (cidrLib.cidrhost net.cidr 1) ];
in
{
  den.routerosDevices.rb5009 = {
    environment = "prd";
    hostname = "rb5009";
    routerosEndpoint = "10.99.0.1";
    certificateAltNames = [
      "DNS:rb5009"
      "DNS:rb5009.kidibox.net"
      "IP:10.99.0.1"
      "IP:192.168.88.1"
    ];
  };

  den.aspects.rb5009 = {
    includes = [
      den.aspects.ros-base
      den.aspects.ros-bgp
      den.aspects.ros-capsman
      den.aspects.ros-dns
      den.aspects.ros-firewall
      den.aspects.ros-qos
    ];

    terragruntInputs = {
      base = {
        dependsOn = [ ];

        inputs =
          sharedInputs
          // commonInputs
          // {
            certificate_alt_names = [
              "DNS:rb5009"
              "DNS:rb5009.kidibox.net"
              "IP:10.99.0.1"
              "IP:192.168.88.1"
            ];

            ntp_server_enabled = true;

            routeros_endpoint = "10.99.0.1";

            # routeros_groups/routeros_users are contributed centrally by
            # modules/network/aspects/ros-base.nix, sourced from
            # den.users.registry/den.groups — not hand-written per device
            # anymore. Per-user passwords still come from 1Password: admin
            # reuses op_item_routeros above, every other user needs an item
            # titled "RB5009 - user - <username>" in vault op_vault.
            # DO NOT apply with the still-TODO registry group/user data, it
            # will destroy the users/groups/ssh keys currently on the router.

            vlans = lib.mapAttrs (_: toVlanInput) networks;

            ethernet_interfaces = {
              "sfp-sfpplus1" = {
                comment = "uplink to crs320";
                tagged = allVlanIds;
              };
              ether1 = {
                comment = "pve1";
                tagged = allVlanIds;
              };
              ether2 = {
                comment = "switch";
                untagged = networks.Management.vlanId;
              };
              ether3 = {
                comment = "capxr1";
                tagged = allVlanIds;
              };
              ether4 = {
                comment = "capxr0";
                tagged = allVlanIds;
              };
              ether7 = {
                comment = "oob";
                bridge_port = false;
                interface_lists = [ "MANAGEMENT" ];
              };
              ether8 = {
                comment = "wan";
                bridge_port = false;
                interface_lists = [ "WAN" ];
              };
            };

            ip_addresses = {
              ether7 = "192.168.88.1/24";
              ether8 = "192.168.100.2/24";
            }
            // lib.mapAttrs (_: net: cidrHostPrefixed net 1) routedNetworks;

            dhcp_clients = [ { interface = "ether8"; } ];

            dhcp_servers = {
              ether7 = {
                cidr = "192.168.88.0/24";
                gateway = null;
                dns_servers = [ ];
              };
            }
            // lib.mapAttrs (_: net: {
              inherit (net) cidr;
              inherit (net) domain;
              gateway = gatewayFor net;
              dns_servers = dnsServersFor net;
              ntp_servers = ntpServersFor net;
            }) routedNetworks;

            dhcp_static_leases = staticLeasesByNetwork config.den.devices;
          };
      };

      capsman = {
        dependsOn = [ "rb5009" ];
        inputs =
          sharedInputs
          // commonInputs
          // {
            capsman_interfaces = [ networks.Management.name ];

            # SSID (field "ssid") + one field per passphrase_groups key.
            op_item_wifi = "RB5009 - wifi";

            passphrase_groups = {
              "${networks.Trusted.name}" = {
                vlan_id = networks.Trusted.vlanId;
              };
              "${networks.Guest.name}" = {
                vlan_id = networks.Guest.vlanId;
                isolated = true;
              };
              "${networks.IotLocal.name}" = {
                vlan_id = networks.IotLocal.vlanId;
                isolated = true;
              };
              "${networks.IotInternet.name}" = {
                vlan_id = networks.IotInternet.vlanId;
                isolated = true;
              };
            };
          };
      };

      dns = {
        dependsOn = [ "rb5009" ];
        inputs =
          sharedInputs
          // commonInputs
          // {
            dns_static_records = {
              "pve1.kidibox.net" = {
                address = "10.0.10.11";
              };
              "ha.kidibox.net" = {
                address = "10.0.10.101";
              };
              "plex.kidibox.net" = {
                address = "10.0.30.100";
              };
              "prowlarr.kidibox.net" = {
                address = "10.0.30.110";
              };
              "radarr.kidibox.net" = {
                address = "10.0.30.120";
              };
              "sonarr.kidibox.net" = {
                address = "10.0.30.130";
              };
              "animarr.kidibox.net" = {
                address = "10.0.30.140";
              };
              "sabnzbd.kidibox.net" = {
                address = "10.0.30.150";
              };
              "doorbell.iot.home.kidibox.net" = {
                address = "10.0.101.100";
              };
            };
          };
      };

      firewall = {
        dependsOn = [ "rb5009" ];
        inputs =
          sharedInputs
          // commonInputs
          // {
            vlans = lib.mapAttrs (_: toFirewallVlanInput) routedNetworks;

            # Only genuinely device/topology-specific rules stay here — the
            # per-network "Allow WAN" rule (den.networks.<name>.internetAccess)
            # and K3s's cluster-specific rules (den.aspects.prd.firewall, in
            # modules/clusters/prd.nix) now arrive via the `firewall` quirk,
            # merged in by modules/network/aspects/ros-firewall.nix.
            vlans_input_rules = {
              "${networks.Trusted.name}" = [
                {
                  action = "accept";
                  dst_address = cidrLib.cidrhost networks.Management.cidr 1;
                  comment = "Allow access to Management from Trusted";
                }
              ];
            };

            vlans_forward_rules = {
              "${networks.Servers.name}" = [
                {
                  action = "accept";
                  out_interface_list = "all";
                  comment = "Allow access to all vlans"; # Because HomeAssistant lives here at the moment
                }
              ];
              "${networks.Media.name}" = [
                {
                  action = "accept";
                  dst_address = "10.0.10.101";
                  src_address = "10.0.30.11";
                  comment = "Allow cloudflared access to HomeAssistant";
                }
              ];
              "${networks.Trusted.name}" = [
                {
                  action = "accept";
                  out_interface = networks.Management.name;
                  comment = "Allow access to Management";
                }
                {
                  action = "accept";
                  out_interface_list = "all";
                  comment = "Allow access to all vlans";
                }
              ];
            };
          };
      };

      # NB: no `dependsOn`, matching the file header's note on this
      # intentional quirk.
      qos = {
        dependsOn = [ ];
        inputs =
          sharedInputs
          // commonInputs
          // {
            wan_interface = "ether8";
            limit_tx = "18M";
            limit_rx = "900M";
          };
      };

      # No cidr arithmetic needed — all real values (ASNs, router ID, node
      # addresses) come from the `bgp`/`k3s-nodes` quirks collected in
      # modules/network/aspects/ros-bgp.nix, not from anything precomputed
      # here.
      bgp = {
        dependsOn = [ "rb5009" ];
        inputs = sharedInputs // commonInputs;
      };
    };
  };
}
