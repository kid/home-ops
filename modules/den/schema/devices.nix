# Device entity schema and instance registry.
#
# A RouterOS device (rb5009, crs320, …) — deliberately its own den entity
# kind rather than den.hosts (den's builtin NixOS/home-manager host entity),
# so a future Talos/NixOS host migration into this repo doesn't collide with
# it. den.devices.<name>.includes = [ ros-base ros-capsman ... ] (via the
# .aspect field below, looked up from the "tf" namespace — see
# modules/terragrunt/namespace.nix) contributes `terragrunt-stacks` class
# content, collected by modules/terragrunt/collect.nix.
{ lib, tf, ... }:
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

            aspect = lib.mkOption {
              type = lib.types.raw;
              default = tf.${name} or { };
              defaultText = "tf.<name>";
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
