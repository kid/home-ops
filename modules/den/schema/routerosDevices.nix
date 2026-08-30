# RouterOS device entity schema and instance registry.
#
# A RouterOS device (rb5009, crs320, …) — deliberately its own den entity
# kind rather than den.hosts (den's builtin NixOS/home-manager host entity),
# so a future Talos/NixOS host migration into this repo doesn't collide with
# it. den.routerosDevices.<name>.includes = [ ros-base ros-capsman ... ] (via
# the .aspect field below, looked up from den.aspects.<name> — same
# convention clusters.nix already uses) contributes `terragrunt-stacks`
# class content, collected by modules/den/batteries/terragrunt-stacks.nix.
#
# Not to be confused with `den.devices` (modules/den/schema/devices.nix) — a
# separate, unrelated registry of network *client* devices (a Proxmox host, a
# camera, ...), used to derive DHCP static leases. That one is named
# `den.devices` specifically because it's the more generic concept; this
# entity kind used to be called `device` too, until that naming collision
# prompted the rename to `routerosDevice`.
{ lib, den, ... }:
{
  config.den.schema.routerosDevice.isEntity = true;

  options.den.routerosDevices = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule (
        { name, ... }:
        {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              default = name;
              description = "RouterOS device name";
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
