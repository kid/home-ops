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
    };
}
