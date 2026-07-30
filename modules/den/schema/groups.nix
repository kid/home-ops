# RouterOS group registry — data-only, no isEntity (mirrors nix-config's own
# groups.nix: groups don't get resolved into the scope tree, they're plain
# data consumed directly by modules/network/aspects/ros-base.nix).
#
# Only covers *custom* RouterOS groups. Built-in groups (full, write, read)
# already exist on every router and are referenced by name in
# den.users.registry.<name>.devices.<device>.group without needing an entry
# here — same as today's placeholder, which never declares "full" either.
{ lib, ... }:
{
  options.den.groups = lib.mkOption {
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
