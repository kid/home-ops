{
  lib,
  config,
  den,
  ...
}:
let
  # Submodule for group-based access grants.
  # accessGrantType = lib.types.submodule {
  #   options.groups = lib.mkOption {
  #     type = lib.types.listOf lib.types.str;
  #     default = [ ];
  #     description = "Groups granted access";
  #   };
  # };

  # Extend user schema with registry fields.
  extendUserSchema =
    { ... }:
    {
      options.email = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "User email address";
      };
      options.groups = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Group memberships for access policy selection";
      };
      options.sshKeys = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "SSH public keys for authorized_keys";
      };
    };

  # Registry entry type — mirrors the standard user entity shape from
  # nix/lib/entities/host.nix so that pipeline self-provide, define-user,
  # and other batteries find the expected attributes (userName, aspect, classes).
  registryUserType = lib.types.submodule (
    { name, config, ... }:
    {
      freeformType = lib.types.attrsOf lib.types.anything;
      imports = [ den.schema.user ];
      config._module.args.user = config;
      options = {
        name = lib.mkOption {
          type = lib.types.str;
          default = name;
          description = "User name (from attrset key)";
        };
        userName = lib.mkOption {
          type = lib.types.str;
          default = name;
          description = "User account name";
        };
        classes = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ "user" ];
          description = "Home management nix classes";
        };
        aspect = lib.mkOption {
          type = lib.types.raw;
          default = if den.aspects ? ${name} then den.aspects.${name} else { };
          defaultText = "den.aspects.<name>";
          description = "Aspect that configures this user";
        };
      };
    }
  );
in
{
  # Registry: standallone, not under fleet.
  options.den.users.registry = lib.mkOption {
    type = lib.types.attrsOf registryUserType;
  };

  config = {
    den.schema.user.isEntity = true;
    den.schema.user.imports = [ extendUserSchema ];

    # Expose registry as falke output for nix eval.
    flake.den.users = config.den.users;
  };
}
