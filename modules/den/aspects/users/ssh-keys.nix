# Provisions authorized SSH keys for a resolved { host, user } scope.
#
# Ported from den's own official templates/fleet-demo/modules/aspects/users/ssh-keys.nix
# (github:denful/den) — writes directly to the real NixOS option path; no
# `.user`-class auto-forwarding involved once on the full registry pattern.
_: {
  den.aspects.ssh-keys.includes = [
    (
      { host, user }:
      {
        name = "ssh-keys/${user.userName}@${host.name}";
        nixos.users.users.${user.userName}.openssh.authorizedKeys.keys = user.sshKeys;
      }
    )
  ];
}
