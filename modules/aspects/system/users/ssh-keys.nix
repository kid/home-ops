# Provisions authorized SSH keys for a resolved { host, user } scope.
# Writes directly to the real NixOS option path — no `.user`-class
# auto-forwarding involved.
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
