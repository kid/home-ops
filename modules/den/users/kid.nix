# kid user registry entry (den.users.registry fleet pattern — see
# modules/den/schema/users.nix, modules/den/policies/users.nix).
#
# TODO: `hashedPassword` is a placeholder and must be replaced with a real
# hash (`mkpasswd -m sha-512`) before this is ever applied to real hardware.
{
  den.users.registry.kid = {
    groups = [ "admins" ]; # den.accessGroups, matched against login gates (modules/den/policies/users.nix)
    sshKeys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAcnmLrPeTJeKsasfU0qn4sP4lBNeOUgRG4iZDS8nyEo kid@vulkan"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHIM3nsk3HxvEcplSqwynh9V2NzlYdI10mrR746SiJZb kid@fw13"
    ];
    hashedPassword = "$y$j9T$aTrKe3LPuhd9zCvCSs4KP1$/V7Blv9MLvM5JWQYjLQrTcc2TzrDpcjHdDdqlSP0Aq2";
    displayName = "Arnaud Rebts";
    mail = [ "arnaud.rebts@gmail.com" ];
  };
}
