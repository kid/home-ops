# Host extensions for the access-control/environment pattern (den's "Access
# Control & Environments" guide): the environment a host is resolved under
# (modules/den/policies/fleet.nix's env-to-hosts) and its own login gates,
# added to that environment's (modules/den/policies/users.nix).
{ lib, ... }:
{
  den.schema.host.imports = [
    {
      options.environment = lib.mkOption {
        type = lib.types.str;
        description = "Name of the den.environments entry this host belongs to";
      };
      # den.accessGroups names; checked in modules/den/policies/users.nix,
      # since den's host merge doesn't apply an enum's element check.
      options.system-access-groups = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Login gates for this host, added to its environment's";
      };
    }
  ];
}
