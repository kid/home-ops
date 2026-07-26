# rb5009 — ported verbatim from tf-stacks/prd/network/rb5009/{terragrunt.hcl,
# capsman,dns,firewall,qos}/terragrunt.hcl.
#
# Two pre-existing quirks ported as-is (not silently fixed, per the plan):
#   - qos has no `dependencies` block, unlike its capsman/dns/firewall
#     siblings (all of which depend on this device's own base stack).
#   - the original firewall leaf's `vlans_forward_rules` HCL object literal
#     defines the "Media" key twice; HCL's object-constructor semantics keep
#     only the *last* occurrence (first is fully dead). Nix attrsets can't
#     even represent a literal duplicate key, so this file only encodes the
#     winning (second) value — same observable result, not a fix.
{
  lib,
  tf,
  config,
  cidrLib,
  ...
}:
let
  environment = config.den.environments.prd;
  inherit (environment) networks;

  allVlanIds = lib.mapAttrsToList (_: net: net.vlanId) networks;
  routedNetworks = lib.filterAttrs (_: net: net.routed) networks;

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

  # Every ros-* stack needs its own onepassword provider auth (1Password
  # item titled "RB5009 - admin", vault "home-ops" — see the K8s
  # ClusterSecretStore convention this mirrors).
  commonInputs = {
    hostname = "rb5009";
    op_vault = "home-ops";
    op_item_routeros = "RB5009 - admin";
  };

  # Matches terragrunt-infra-catalog's ros-base module `vlans` variable object shape
  # (name, vlan_id, mtu?, interface_lists?).
  toVlanInput =
    net:
    {
      inherit (net) name;
      vlan_id = net.vlanId;
    }
    // lib.optionalAttrs (net.mtu != null) { inherit (net) mtu; }
    // lib.optionalAttrs (net.interfaceLists != [ ]) { interface_lists = net.interfaceLists; };

  # terragrunt-infra-catalog's ros-firewall module `vlans` variable only wants name+vlan_id.
  toFirewallVlanInput = net: {
    inherit (net) name;
    vlan_id = net.vlanId;
  };

  cidrHostPrefixed = net: hostnum: "${cidrLib.cidrhost net.cidr hostnum}/${toString net.prefix}";

  gatewayFor = net: if net.dhcpGateway != null then net.dhcpGateway else cidrLib.cidrhost net.cidr 1;
  dnsServersFor =
    net: if net.dhcpDnsServers != null then net.dhcpDnsServers else [ (cidrLib.cidrhost net.cidr 1) ];
  ntpServersFor =
    net: if net.dhcpNtpServers != null then net.dhcpNtpServers else [ (cidrLib.cidrhost net.cidr 1) ];
in
{
  den.devices.rb5009 = {
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

  tf.rb5009 = {
    includes = [
      tf.ros-base
      tf.ros-capsman
      tf.ros-dns
      tf.ros-firewall
      tf.ros-qos
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

            # TODO: fill in with the real (non-secret) values from
            # secrets/prd/routeros.sops.yaml's groups/users sections before
            # applying. Per-user passwords come from 1Password instead:
            # admin reuses op_item_routeros above, every other user needs an
            # item titled "RB5009 - user - <username>" in vault op_vault.
            # DO NOT apply with these placeholders, it will destroy the
            # users/groups/ssh keys currently on the router.
            routeros_groups = {
              "external-dns" = {
                policies = [ ];
              }; # TODO
              metrics = {
                policies = [ ];
              }; # TODO
            };
            routeros_users = {
              admin = { };
              kid = {
                group = "full"; # TODO verify
                ssh_keys = [ ]; # TODO
              };
              "external-dns" = {
                group = "external-dns";
              }; # TODO verify
              metrics = {
                group = "metrics";
              }; # TODO verify
            };

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

            dhcp_static_leases = {
              "${networks.Management.name}" = [
                {
                  name = "crs320";
                  mac = "f4:1e:57:d1:75:94";
                  address = cidrLib.cidrhost networks.Management.cidr 2;
                }
                {
                  name = "capxr0";
                  mac = "48:a9:8a:cc:6d:62";
                  address = cidrLib.cidrhost networks.Management.cidr 10;
                }
                {
                  name = "capxr1";
                  mac = "48:a9:8a:ba:2a:6e";
                  address = cidrLib.cidrhost networks.Management.cidr 11;
                }
                {
                  name = "pve0-ipmi";
                  mac = "d0:50:99:f7:ee:15";
                  address = cidrLib.cidrhost networks.Management.cidr ((networks.Servers.vlanId * 256) + 10);
                }
                {
                  name = "pikvm";
                  mac = "dc:a6:32:06:69:9a";
                  address = cidrLib.cidrhost networks.Management.cidr ((networks.Servers.vlanId * 256) + 11);
                }
              ];
              "${networks.Servers.name}" = [
                {
                  name = "pve0";
                  mac = "a6:34:58:9f:98:09";
                  address = cidrLib.cidrhost networks.Servers.cidr 10;
                }
                {
                  name = "pve1";
                  mac = "be:4f:11:f4:ba:61";
                  address = cidrLib.cidrhost networks.Servers.cidr 11;
                }
                {
                  name = "homeassistant";
                  mac = "52:54:00:93:9b:8f";
                  address = cidrLib.cidrhost networks.Servers.cidr 101;
                }
              ];
              "${networks.Media.name}" = [
                {
                  name = "cloudflared1";
                  mac = "bc:24:11:bf:d2:cb";
                  address = cidrLib.cidrhost networks.Media.cidr 11;
                }
                {
                  name = "truenas";
                  mac = "bc:24:11:9f:50:bf";
                  address = cidrLib.cidrhost networks.Media.cidr 126;
                }
              ];
              "${networks.Trusted.name}" = [
                {
                  name = "everything-presence-lite-20b1c4";
                  mac = "08:d1:f9:20:b1:c4";
                  address = cidrLib.cidrhost networks.Trusted.cidr 108;
                }
                {
                  name = "prtsrv";
                  mac = "bc:24:11:42:5b:fc";
                  address = cidrLib.cidrhost networks.Trusted.cidr 137;
                }
                {
                  name = "shield";
                  mac = "48:b0:2d:18:ec:cd";
                  address = cidrLib.cidrhost networks.Trusted.cidr 212;
                }
              ];
              "${networks.IotLocal.name}" = [
                {
                  name = "doorbell";
                  mac = "ec:71:db:26:a9:37";
                  address = cidrLib.cidrhost networks.IotLocal.cidr 10;
                }
                {
                  name = "litters camera";
                  mac = "e0:01:c7:e4:e0:f3";
                  address = cidrLib.cidrhost networks.IotLocal.cidr 11;
                }
                {
                  name = "LGwebOSTV";
                  mac = "f0:86:20:10:84:18";
                  address = cidrLib.cidrhost networks.IotLocal.cidr 20;
                }
                {
                  name = "denon";
                  mac = "00:06:78:40:24:0a";
                  address = cidrLib.cidrhost networks.IotLocal.cidr 21;
                }
                {
                  name = "Somfy Box";
                  mac = "88:12:ac:04:36:44";
                  address = cidrLib.cidrhost networks.IotLocal.cidr 30;
                }
              ];
              "${networks.IotInternet.name}" = [
                {
                  name = "roborock-vacuum-a38";
                  mac = "b0:4a:39:98:1c:cb";
                  address = cidrLib.cidrhost networks.IotInternet.cidr 30;
                }
                {
                  name = "dreame_vacuum_r2465a";
                  mac = "70:c9:32:4e:21:7d";
                  address = cidrLib.cidrhost networks.IotInternet.cidr 31;
                }
              ];
            };
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
              "pve0.kidibox.net" = {
                address = "10.0.10.10";
              };
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

            vlans_input_rules = {
              "${networks.Trusted.name}" = [
                {
                  action = "accept";
                  dst_address = cidrLib.cidrhost networks.Management.cidr 1;
                  comment = "Allow access to Management from Trusted";
                }
              ];
              "${networks.Talos.name}" = [
                {
                  action = "accept";
                  dst_address = cidrLib.cidrhost networks.Management.cidr 1;
                  dst_port = 443;
                  protocol = "tcp";
                  comment = "Allow access to Management from Talos for external-dns";
                }
                {
                  action = "accept";
                  dst_address = cidrLib.cidrhost networks.Management.cidr 1;
                  dst_port = 8729;
                  protocol = "tcp";
                  comment = "Allow access to Management from Talos for mikrotik-exporter";
                }
              ];
            };

            vlans_forward_rules = {
              "${networks.Management.name}" = [
                {
                  action = "accept";
                  out_interface_list = "WAN";
                  comment = "Allow WAN from Management";
                }
              ];
              "${networks.Servers.name}" = [
                {
                  action = "accept";
                  out_interface_list = "WAN";
                  comment = "Allow WAN";
                }
                {
                  action = "accept";
                  out_interface_list = "all";
                  comment = "Allow access to all vlans"; # Because HomeAssistant lives here at the moment
                }
              ];
              # NB: the hand-written firewall/terragrunt.hcl defines this key
              # ("Media") twice; HCL's object-constructor keeps only the last
              # occurrence, so the first (WAN-only) rule set was already dead.
              # Only the winning (second) value is encoded here.
              "${networks.Media.name}" = [
                {
                  action = "accept";
                  out_interface_list = "WAN";
                  comment = "Allow WAN";
                }
                {
                  action = "accept";
                  dst_address = "10.0.10.101";
                  src_address = "10.0.30.11";
                  comment = "Allow cloudflared access to HomeAssistant";
                }
              ];
              "${networks.Talos.name}" = [
                {
                  action = "accept";
                  out_interface_list = "WAN";
                  comment = "Allow WAN";
                }
                {
                  action = "accept";
                  dst_address = "10.0.42.0/24";
                  comment = "Allow Traffic to load balancer ips";
                }
                {
                  action = "accept";
                  dst_address = cidrLib.cidrhost networks.Management.cidr 2;
                  dst_port = 8729;
                  protocol = "tcp";
                  comment = "Allow access to crs320 for mikrotik-exporter";
                }
              ];
              "${networks.IotLocal.name}" = [
                {
                  action = "accept";
                  out_interface_list = "WAN";
                  comment = "Allow WAN";
                  disabled = true;
                }
              ];
              "${networks.IotInternet.name}" = [
                {
                  action = "accept";
                  out_interface_list = "WAN";
                  comment = "Allow WAN";
                }
              ];
              "${networks.Trusted.name}" = [
                {
                  action = "accept";
                  out_interface_list = "WAN";
                  comment = "Allow WAN";
                }
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
              "${networks.Guest.name}" = [
                {
                  action = "accept";
                  out_interface_list = "WAN";
                  comment = "Allow WAN";
                }
              ];
              "${networks.RosLab.name}" = [
                {
                  action = "accept";
                  out_interface_list = "WAN";
                  comment = "Allow WAN";
                }
              ];
            };
          };
      };

      # NB: no `dependsOn` — unlike capsman/dns/firewall, qos does not
      # depend on this device's own base stack in the hand-written HCL
      # either. Preserved as-is (see file header).
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
    };
  };
}
