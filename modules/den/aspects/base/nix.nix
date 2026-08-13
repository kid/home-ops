# Generic nix-daemon settings (nix.settings.*) — add further nix.conf knobs
# here as they come up, not just trusted-users.
{
  den.aspects.base.nix.nixos = {
    nix.settings.trusted-users = [
      "root"
      "@wheel"
    ];
  };
}
