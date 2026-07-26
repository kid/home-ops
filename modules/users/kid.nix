# kid user aspect. Shape ported from nixopslab's modules/users/kid.nix, but
# with this repo's own key material — do not reuse nixopslab's, it's a
# different machine/user pairing.
#
# TODO: `hashedPassword` is a placeholder and must be replaced with a real
# hash (`mkpasswd -m sha-512`) before this is ever applied to real hardware.
{
  den.aspects.kid.nixos = {
    security.sudo.wheelNeedsPassword = false;
    users.users.kid = {
      isNormalUser = true;
      extraGroups = [ "wheel" ];
      hashedPassword = "!"; # TODO: replace before applying — "!" disables password login entirely for now
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAcnmLrPeTJeKsasfU0qn4sP4lBNeOUgRG4iZDS8nyEo kid@vulkan"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHIM3nsk3HxvEcplSqwynh9V2NzlYdI10mrR746SiJZb kid@fw13"
      ];
    };
  };
}
