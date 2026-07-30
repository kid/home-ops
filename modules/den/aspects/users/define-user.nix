# Creates the base NixOS account for a resolved { host, user } scope.
#
# Written explicitly rather than relying on den's own `define-user` battery
# (used by templates/fleet-demo) since that battery isn't verified against
# this repo's pinned den rev — this is one less unverified API to depend on.
_: {
  den.aspects.define-user.includes = [
    (
      { host, user }:
      {
        name = "define-user/${user.userName}@${host.name}";
        nixos.users.users.${user.userName} = {
          isNormalUser = true;
          inherit (user) extraGroups hashedPassword;
        };
      }
    )
  ];
}
