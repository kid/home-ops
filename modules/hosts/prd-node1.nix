# prd-node1 — bare-metal k3s node for the `prd` cluster. Adapted from
# nixopslab's modules/hosts/k3s-node1.nix with all libvirt/VM-specific
# content removed (no qemu-guest profile, no libvirt.* fields) — this
# installs directly onto real hardware via nixos-anywhere
# (`nix run .#nixos-anywhere-install`, modules/flake/nixos-anywhere.nix),
# not a VM.
#
# TODO before this can ever be installed for real:
#   - settings.disko.zfs-disk-single.settings.device_id: currently a
#     placeholder, must be the target machine's real stable disk id
#     (`ls /dev/disk/by-id/` from the nixos-anywhere installer environment).
#   - networking.hostId: currently a placeholder, must be a stable random
#     8-hex-digit string unique to this machine (required by ZFS).
#   - Which physical box this targets (pve0/pve1 or other) and what happens
#     to whatever currently runs there under Proxmox — out of scope for this
#     Nix code, a decision the user makes before ever running the install.
{ den, ... }:
{
  den.hosts.x86_64-linux.prd-node1 = {
    k3s.clusterName = "prd";
    settings.disko.zfs-disk-single.settings.device_id = "/dev/disk/by-id/PLACEHOLDER";
  };

  den.aspects.prd-node1.nixos =
    { lib, pkgs, ... }:
    {
      boot.loader.systemd-boot.enable = true;
      boot.loader.efi.canTouchEfiVariables = true;

      # Stable hostId required by ZFS (hex, unique per machine) — placeholder,
      # generate a real one before installing (e.g. `head -c4 /dev/urandom | od -A none -t x4`).
      networking.hostId = lib.mkDefault "00000000";

      networking.hostName = "prd-node1";
      networking.useDHCP = true;
      networking.useNetworkd = true;

      time.timeZone = "UTC";
      i18n.defaultLocale = "en_US.UTF-8";

      users.mutableUsers = false;
      security.sudo.enable = true;

      services.openssh.enable = true;

      system.stateVersion = "26.05";

      environment.systemPackages = [ pkgs.htop ];
    };

  den.aspects.prd-node1.includes = [
    den.aspects.disko.zfs-disk-single
    den.aspects.impermanence
    den.aspects.impermanence.tmpfs
    den.aspects.k3s-server
    den.aspects.kid
  ];
}
