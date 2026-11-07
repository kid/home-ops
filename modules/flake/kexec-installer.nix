# The kexec installer nixos-anywhere boots before it runs disko, built from
# this flake's nixpkgs: disko's udevadm must match the installer's udevd, or
# `udevadm settle` returns before the partition links exist.
{ inputs, ... }:
{
  flake-file.inputs.nixos-images = {
    url = "github:nix-community/nixos-images";
    inputs.nixos-unstable.follows = "nixpkgs";
    inputs.nixos-stable.follows = "nixpkgs";
  };

  perSystem =
    { pkgs, ... }:
    {
      packages.kexec-installer =
        (pkgs.nixos [
          inputs.nixos-images.nixosModules.kexec-installer
          inputs.nixos-images.nixosModules.noninteractive
          { system.kexec-installer.name = "nixos-kexec-installer-noninteractive"; }
        ]).config.system.build.kexecInstallerTarball;
    };
}
