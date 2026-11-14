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

      # The bare-metal hosts are ZFS-only, and LVM would scan their zvols and
      # activate volume groups guests created on them. miroir-node turns it on.
      services.lvm.enable = lib.mkDefault false;
    };
}
