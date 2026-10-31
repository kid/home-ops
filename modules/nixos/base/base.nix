# Settings common to every host in the fleet: srvos's server profile and
# mixins.
{ inputs, ... }:
{
  flake-file.inputs.srvos = {
    url = "github:nix-community/srvos";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  den.aspects.base.nixos.imports = with inputs.srvos.nixosModules; [
    server
    mixins-nix-experimental
    mixins-systemd-boot
    mixins-terminfo
  ];
}
