# Typed per-host aspect settings (den's Aspect Settings guide): an aspect
# declares `settings.<name> = lib.mkOption { ... }` next to its classes, a
# host sets `settings.<aspect path>.<name>`, and the aspect reads
# `host.settings.<aspect path>.<name>`.
{ den, lib, ... }:
{
  den.reservedKeys = [ "settings" ];

  den.schema.host.imports = [
    {
      options.settings = lib.mkOption {
        type = import ./_settings-type.nix { inherit den lib; };
        default = { };
        description = "Per-aspect typed settings";
      };
    }
  ];
}
