# An Incus VM installed with nixos-anywhere (tf-catalog/modules/incus-k3s).
# One disk: an ESP, and an LVM VG with a fixed-size root LV. The rest of the
# VG is free for miroir, which makes its thin pool there: `vg-miroir` is the
# VG of its `default` pool. No den.aspects.disko: that one turns on
# disko-zfs.
{ inputs, ... }:
{
  den.aspects.incus-vm.nixos =
    { modulesPath, ... }:
    {
      imports = [
        (modulesPath + "/profiles/qemu-guest.nix")
        inputs.disko.nixosModules.disko
      ];

      boot.loader.systemd-boot.enable = true;
      boot.loader.efi.canTouchEfiVariables = true;

      virtualisation.incus.agent.enable = true;

      disko.devices = {
        disk.root = {
          type = "disk";
          device = "/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_incus_root";
          content = {
            type = "gpt";
            partitions = {
              ESP = {
                size = "512M";
                type = "EF00";
                content = {
                  type = "filesystem";
                  format = "vfat";
                  mountpoint = "/boot";
                  mountOptions = [ "umask=0077" ];
                };
              };
              lvm = {
                size = "100%";
                content = {
                  type = "lvm_pv";
                  vg = "vg-miroir";
                };
              };
            };
          };
        };
        lvm_vg.vg-miroir = {
          type = "lvm_vg";
          lvs.root = {
            size = "40G";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/";
            };
          };
        };
      };
    };
}
