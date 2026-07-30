# Device entity schema and instance registry.
#
# A RouterOS device (rb5009, crs320, …) — deliberately its own den entity
# kind rather than den.hosts (den's builtin NixOS/home-manager host entity),
# so a future Talos/NixOS host migration into this repo doesn't collide with
# it. den.devices.<name>.includes = [ ros-base ros-capsman ... ] (via the
# .aspect field below, looked up from den.aspects.<name> — same convention
# clusters.nix already uses) contributes `terragrunt-stacks` class content,
# collected by modules/terragrunt/collect.nix.
{ lib, den, ... }:
{
  config.den.schema.device.isEntity = true;

  options.den.devices = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule (
        { name, ... }:
        {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              default = name;
              description = "Device name";
            };

            environment = lib.mkOption {
              type = lib.types.str;
              description = "Name of the den.environments entry this device belongs to";
            };

            hostname = lib.mkOption {
              type = lib.types.str;
              default = name;
              description = "RouterOS hostname (system identity)";
            };

            routerosEndpoint = lib.mkOption {
              type = lib.types.str;
              description = "Address (host[:port] or URL) the routeros provider connects to";
            };

            certificateAltNames = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "Subject alt names for this device's TLS certificate";
            };

            # This device's own address/MAC on the Management VLAN, if it's
            # directly addressable there — the single source of truth for
            # other devices that need to reference it (e.g. rb5009's
            # dhcp_static_leases/firewall-rule entries for crs320), instead
            # of duplicating the literal. Single producer (this device's own
            # declaration) / single consumer (whichever device reads it) —
            # a plain field read, not resolve.to/quirks, same reasoning as
            # den.users.registry (see AGENTS.md's Users section).
            managementHostNum = lib.mkOption {
              type = lib.types.nullOr lib.types.ints.unsigned;
              default = null;
              description = "This device's own host-number on the Management VLAN";
            };

            managementMac = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "This device's own MAC address on the Management VLAN";
            };

            aspect = lib.mkOption {
              type = lib.types.raw;
              default = den.aspects.${name} or { };
              defaultText = "den.aspects.<name>";
              description = "Aspect that configures this device";
            };
          };
        }
      )
    );
    default = { };
    description = "RouterOS device entity registry for den";
  };
}
