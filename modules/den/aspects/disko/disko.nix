# disko module wiring for NixOS hosts. Adapted from nixopslab's
# modules/den/aspects/disko/disko.nix — dropped the vmTools.kernelImage
# overlay workaround and disko's image-builder entirely, since that exists
# only to fix building a *qcow2 image* for a VM's disk. prd hosts install
# via nixos-anywhere directly onto real hardware (disko partitions the
# machine's actual disks live over SSH); there's no image to build.
{ inputs, den, ... }:
{
  flake-file.inputs.disko = {
    # Pinned to nix-community/disko#1277 (unmerged): fixes make-disk-image.nix
    # passing an aggregated module tree as vmTools' `kernel` arg, which broke
    # against a nixpkgs vmTools API change (kernel/kernelModules split) —
    # needed for system.build.vmWithDisko (see modules/hosts/test-vm.nix).
    # Switch back to nix-community/disko once merged upstream.
    url = "github:AlexLov/disko/6747342da148f6cb28c8405a70fe00455a0ba027";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  # Manages ZFS datasets declaratively on every activation/boot (not just at
  # disko's install-time format), so aspects can request datasets they need
  # via the `datasets` quirk (see zfs-datasets-collector.nix) without a
  # reformat. Auto-adopts datasets already declared under disko.devices.
  flake-file.inputs.disko-zfs = {
    url = "github:numtide/disko-zfs";
    inputs.nixpkgs.follows = "nixpkgs";
    inputs.flake-parts.follows = "flake-parts";
    inputs.disko.follows = "disko";
  };

  den.aspects.disko = {
    includes = [ den.aspects.disko.zfs-datasets-collector ];

    nixos = {
      imports = [
        inputs.disko.nixosModules.disko
        inputs.disko-zfs.nixosModules.default
      ];
      disko.zfs.enable = true;
    };
  };
}
