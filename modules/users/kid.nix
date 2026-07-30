# kid user registry entry. Shape ported from nixopslab's modules/users/kid.nix
# originally, now migrated onto the den.users.registry fleet pattern (see
# modules/den/schema/users.nix, modules/den/policies/users.nix) — with this
# repo's own key material, do not reuse nixopslab's.
#
# TODO: `hashedPassword` is a placeholder and must be replaced with a real
# hash (`mkpasswd -m sha-512`) before this is ever applied to real hardware.
{
  den.users.registry.kid = {
    groups = [ "admin" ]; # access-policy group, matched by fleet.user-access.by-host
    extraGroups = [ "wheel" ];
    sshKeys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAcnmLrPeTJeKsasfU0qn4sP4lBNeOUgRG4iZDS8nyEo kid@vulkan"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHIM3nsk3HxvEcplSqwynh9V2NzlYdI10mrR746SiJZb kid@fw13"
    ];
    devices.rb5009.group = "full"; # TODO verify, ported from existing placeholder
    devices.crs320.group = "full"; # TODO verify, ported from existing placeholder
  };
}
