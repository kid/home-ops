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
    let
      # Sets boot.initrd.systemd.enable, which nixpkgs now rejects as a removed
      # option (systemd is the only initrd), so evaluation fails. Keep its
      # initrd service, which restores SSH keys and network config after the
      # kexec, without that line. Drop once nix-community/nixos-images#453 is
      # fixed.
      restoreRemoteAccess = "${inputs.nixos-images}/nix/restore-remote-access.nix";
    in
    {
      packages.kexec-installer =
        (pkgs.nixos [
          inputs.nixos-images.nixosModules.kexec-installer
          inputs.nixos-images.nixosModules.noninteractive
          { system.kexec-installer.name = "nixos-kexec-installer-noninteractive"; }
          {
            disabledModules = [ restoreRemoteAccess ];
            boot.initrd.systemd.services = (import restoreRemoteAccess).boot.initrd.systemd.services;
          }
        ]).config.system.build.kexecInstallerTarball;
    };
}
