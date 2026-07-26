# disko module wiring for NixOS hosts. Adapted from nixopslab's
# modules/den/aspects/disko/disko.nix — dropped the vmTools.kernelImage
# overlay workaround and disko's image-builder entirely, since that exists
# only to fix building a *qcow2 image* for a VM's disk. prd hosts install
# via nixos-anywhere directly onto real hardware (disko partitions the
# machine's actual disks live over SSH); there's no image to build.
{ inputs, ... }:
{
  flake-file.inputs.disko = {
    url = "github:nix-community/disko";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  den.aspects.disko.nixos = {
    imports = [ inputs.disko.nixosModules.disko ];
  };
}
