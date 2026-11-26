# Lets host-included aspects add groups to the privileged user without naming
# it: they set users.privilegedGroups, kid includes this. Declares the option,
# so only one user per host may include it.
_: {
  den.aspects.privileged-user.includes = [
    (
      { host, user }:
      {
        name = "privileged-user/${user.userName}@${host.name}";
        nixos =
          { config, lib, ... }:
          {
            options.users.privilegedGroups = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "Groups the host's privileged user joins";
            };
            config.users.users.${user.userName}.extraGroups = config.users.privilegedGroups;
          };
      }
    )
  ];
}
