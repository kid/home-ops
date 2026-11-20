# Settings common to every host in the fleet: srvos's server profile and
# mixins.
{ inputs, ... }:
{
  flake-file.inputs.srvos = {
    url = "github:nix-community/srvos";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  den.aspects.base.nixos =
    { lib, ... }:
    {
      imports = with inputs.srvos.nixosModules; [
        server
        mixins-nix-experimental
        mixins-systemd-boot
        mixins-terminfo
      ];

      # The release every current host was installed with. Never bump it:
      # that changes it for every existing host. A host installed from a
      # later release sets its own.
      system.stateVersion = lib.mkDefault "26.05";

      # The hosts are ZFS-only, and LVM would scan their zvols and activate
      # volume groups guests created on them.
      services.lvm.enable = lib.mkDefault false;

      # Drops system generations older than two weeks, then everything no
      # longer rooted, including the in-cluster CI runner's build outputs
      # (modules/kubernetes/actions-runner-controller): the next CI run after
      # it rebuilds what changed since the host's own system.
      nix.gc = {
        automatic = true;
        dates = "weekly";
        options = "--delete-older-than 14d";
      };

      # kid's public Cachix cache, which nixfiles' and neovim's CI push to.
      # On k3s-prd-0 it also serves the in-cluster CI runner, which can't add
      # a substituter itself: the daemon doesn't trust it.
      nix.settings = {
        extra-substituters = [ "https://kidibox.cachix.org" ];
        extra-trusted-public-keys = [ "kidibox.cachix.org-1:BN875x9JUW61souPxjf7eA5Uh2k3A1OSA1JIb/axGGE=" ];
      };
    };
}
