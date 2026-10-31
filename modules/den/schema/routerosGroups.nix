# RouterOS group registry — data-only, no isEntity, consumed directly by
# modules/routeros/base.nix.
#
# Holds the policies of *custom* RouterOS groups, keyed by the name of the
# `routeros`-labelled den.accessGroups group users reach it through.
# Built-in groups (full, write, read) already exist on every router and need
# no entry here.
{ lib, ... }:
{
  options.den.routerosGroups = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule (
        { name, ... }:
        {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              default = name;
              description = "Group name";
            };
            description = lib.mkOption {
              type = lib.types.str;
              default = "";
              description = "Human-readable description of the group";
            };
            policies = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "RouterOS group policies";
            };
          };
        }
      )
    );
    default = { };
    description = "Custom RouterOS group definitions";
  };
}
