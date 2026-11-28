# CAPsMAN on a RouterOS device: the Wi-Fi of the cAP XR access points it
# provisions, from the device's routerosInputs.capsman (see
# modules/fleet/routeros/rb5009.nix). The SSID and each passphrase group's
# passphrase are fields of the op_item_wifi 1Password item.
{ lib, ... }:
let
  # One per frequency plan an access point's radio uses.
  channels = {
    channel_6 = {
      name = "channel-6";
      width = "20mhz";
      frequency = [ "2437" ];
    };
    channel_11 = {
      name = "channel-11";
      width = "20mhz";
      frequency = [ "2462" ];
    };
    capxr0 = {
      name = "capxr0";
      width = "20/40/80mhz";
      frequency = [ "5500-5720" ];
      skip_dfs_channels = "10min-cac";
    };
    U-NII-1 = {
      name = "U-NII-1";
      width = "20/40/80mhz";
      frequency = [ "5180-5240" ];
      skip_dfs_channels = "10min-cac";
    };
    U-NII-2C = {
      name = "U-NII-2C";
      width = "20/40/80mhz";
      frequency = [ "5480-5720" ];
      skip_dfs_channels = "10min-cac";
    };
    capxr1 = {
      name = "capxr1";
      width = "20/40/80mhz";
      frequency = [ "5180-5340" ];
      skip_dfs_channels = "10min-cac";
    };
  };

  # Each access point's channel per band; its 5 GHz radio also serves the
  # <ssid>-5Ghz network.
  accessPoints = {
    capxr0 = {
      "2g" = "channel_6";
      "5g" = "U-NII-2C";
    };
    capxr1 = {
      "2g" = "channel_11";
      "5g" = "U-NII-1";
    };
  };

  ssid = "\${local.capsman_wifi_ssid}";

  # name -> its configuration's channel resource, tx power and SSID.
  configurations =
    accessPoints
    |> lib.concatMapAttrs (
      ap: bands: {
        "${ap}-2g" = {
          channel = bands."2g";
          tx_power = 10;
          inherit ssid;
        };
        "${ap}-5g" = {
          channel = bands."5g";
          tx_power = 23;
          inherit ssid;
        };
        "${ap}-5g-only" = {
          channel = bands."5g";
          tx_power = 23;
          ssid = "${ssid}-5Ghz";
        };
      }
    );

  # name -> its access point, band and configurations.
  provisionings =
    accessPoints
    |> lib.concatMapAttrs (
      ap: _: {
        "${ap}-2g" = {
          inherit ap;
          band = "2g";
          master = "${ap}-2g";
        };
        "${ap}-5g" = {
          inherit ap;
          band = "5g";
          master = "${ap}-5g";
          slaves = [ "${ap}-5g-only" ];
        };
      }
    );

  configurationName = name: "\${routeros_wifi_configuration.capsman_${name}.name}";
in
{
  den.aspects.routeros.capsman.tofu =
    { routerosDevice, ... }:
    let
      inherit (routerosDevice.aspect.routerosInputs.capsman) inputs;
    in
    {
      data.onepassword_item.capsman_wifi = {
        vault = inputs.op_vault;
        title = inputs.op_item_wifi;
      };

      locals = {
        capsman_wifi_fields = "\${{ for field in flatten([for section in data.onepassword_item.capsman_wifi.section : section.field]) : field.label => field.value }}";
        capsman_wifi_ssid = ''''${local.capsman_wifi_fields["ssid"]}'';
      };

      resource.routeros_wifi_capsman.capsman = {
        enabled = true;
        interfaces = inputs.capsman_interfaces;
        upgrade_policy = "suggest-same-version";
      };

      resource.routeros_wifi_channel = lib.mapAttrs' (
        name: channel: lib.nameValuePair "capsman_${name}" channel
      ) channels;

      resource.routeros_wifi_security_multi_passphrase = lib.mapAttrs' (
        group: settings:
        lib.nameValuePair "capsman_${group}" {
          group = ssid;
          inherit (settings) vlan_id;
          isolation = settings.isolated or false;
          passphrase = ''''${local.capsman_wifi_fields["${group}"]}'';
        }
      ) inputs.passphrase_groups;

      resource.routeros_wifi_security.capsman_wpa2 = {
        depends_on =
          inputs.passphrase_groups
          |> lib.attrNames
          |> map (group: "routeros_wifi_security_multi_passphrase.capsman_${group}");
        name = "wpa2";
        authentication_types = [ "wpa2-psk" ];
        encryption = [ "ccmp" ];
        ft = true;
        ft_over_ds = true;
        ft_preserve_vlanid = true;
        disable_pmkid = true;
        connect_priority = "0/1";
        management_protection = "allowed";
        multi_passphrase_group = ssid;
      };

      resource.routeros_wifi_steering.capsman = {
        name = "default";
        rrm = true;
        wnm = true;
      };

      resource.routeros_wifi_datapath = {
        capsman_default = {
          name = "default";
          bridge = inputs.bridge_name;
        };
        capsman_lan = {
          name = "lan";
          bridge = "bridge1";
          vlan_id = 100;
        };
      };

      resource.routeros_wifi_configuration = lib.mapAttrs' (
        name: configuration:
        lib.nameValuePair "capsman_${name}" {
          inherit name;
          inherit (configuration) ssid tx_power;
          country = "Belgium";
          multicast_enhance = "enabled";
          dtim_period = 4;
          channel.config = "\${routeros_wifi_channel.capsman_${configuration.channel}.name}";
          datapath.config = "\${routeros_wifi_datapath.capsman_default.name}";
          security.config = "\${routeros_wifi_security.capsman_wpa2.name}";
          steering.config = "\${routeros_wifi_steering.capsman.name}";
        }
      ) configurations;

      resource.routeros_wifi_provisioning = lib.mapAttrs' (
        name: p:
        lib.nameValuePair "capsman_${name}" (
          {
            identity_regexp = p.ap;
            name_format = "wifi${p.band}-%I";
            action = "create-dynamic-enabled";
            supported_bands = [ "${if p.band == "2g" then "2" else "5"}ghz-ax" ];
            master_configuration = configurationName p.master;
          }
          // lib.optionalAttrs (p ? slaves) { slave_configurations = map configurationName p.slaves; }
        )
      ) provisionings;

      # From the catalog's ros-capsman module, which the stack called until
      # these were ported. Drop once applied.
      moved =
        let
          # The module's address of each of a type's resources -> its own.
          renamed =
            type: names: rename:
            names
            |> map (name: lib.nameValuePair "${type}.${name}" "${type}.${rename name}")
            |> lib.listToAttrs;
          prefixed = name: "capsman_${name}";
        in
        {
          "routeros_wifi_capsman.settings" = "routeros_wifi_capsman.capsman";
          "routeros_wifi_security.wpa2" = "routeros_wifi_security.capsman_wpa2";
          "routeros_wifi_steering.default" = "routeros_wifi_steering.capsman";
          "routeros_wifi_datapath.default" = "routeros_wifi_datapath.capsman_default";
          "routeros_wifi_datapath.lan" = "routeros_wifi_datapath.capsman_lan";
        }
        // renamed "routeros_wifi_channel" (lib.attrNames channels) prefixed
        // renamed "routeros_wifi_configuration" (lib.attrNames configurations) prefixed
        // renamed "routeros_wifi_provisioning" (lib.attrNames provisionings) prefixed
        // (
          inputs.passphrase_groups
          |> lib.mapAttrs' (
            group: _:
            lib.nameValuePair ''routeros_wifi_security_multi_passphrase.groups["${group}"]'' "routeros_wifi_security_multi_passphrase.capsman_${group}"
          )
        )
        |> lib.mapAttrsToList (
          from: to: {
            from = "module.capsman.${from}";
            inherit to;
          }
        );
    };
}
