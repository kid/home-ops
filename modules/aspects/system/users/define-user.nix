# Creates the base NixOS account for a resolved { host, user } scope.
# extraGroups are the user's den.accessGroups closure labelled `posix`
# (modules/den/policies/users.nix), each also declared as a NixOS group.
#
# Written explicitly rather than relying on den's own `define-user` battery
# (used by templates/fleet-demo) since that battery isn't verified against
# this repo's pinned den rev — this is one less unverified API to depend on.
{ acl, lib, ... }:
{
  den.aspects.define-user.includes = [
    (
      { host, user }:
      let
        posixGroups = user.groups |> acl.closure |> acl.labelled "posix";
      in
      {
        name = "define-user/${user.userName}@${host.name}";
        nixos = {
          users.users.${user.userName} = {
            isNormalUser = true;
            inherit (user) hashedPassword;
            extraGroups = posixGroups;
          };
          users.groups = lib.genAttrs posixGroups (_: { });
        };
      }
    )
  ];
}
