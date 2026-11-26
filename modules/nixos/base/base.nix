# Settings common to every NixOS host, servers and desktops: srvos mixins,
# the state version default and kid's binary cache. The server-only srvos
# profile lives in den.aspects.server (modules/nixos/server.nix).
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
        mixins-nix-experimental
        mixins-systemd-boot
        mixins-terminfo
      ];

      # The release every current host was installed with. Never bump it:
      # that changes it for every existing host. A host installed from a
      # later release sets its own.
      system.stateVersion = lib.mkDefault "26.05";

      # kid's public Cachix cache, which neovim's CI pushes to.
      # On k3s-prd-0 it also serves the in-cluster CI runner, which can't add
      # a substituter itself: the daemon doesn't trust it.
      nix.settings = {
        extra-substituters = [ "https://kidibox.cachix.org" ];
        extra-trusted-public-keys = [ "kidibox.cachix.org-1:BN875x9JUW61souPxjf7eA5Uh2k3A1OSA1JIb/axGGE=" ];
      };
    };
}
