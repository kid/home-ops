# Plain VM disk: GPT, ESP on /boot, ext4 root. For Incus VMs installed with
# nixos-anywhere (tf-catalog/modules/incus-k3s). No den.aspects.disko: that
# one turns on disko-zfs.
{ inputs, lib, ... }:
{
  den.aspects.disko.vm-ext4 = {
    settings.device = lib.mkOption {
      type = lib.types.str;
      description = "Disk disko partitions (e.g. /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_incus_root)";
    };

    nixos =
      { host, ... }:
      {
        imports = [ inputs.disko.nixosModules.disko ];

        disko.devices.disk.root = {
          type = "disk";
          inherit (host.settings.disko.vm-ext4.settings) device;
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
              root = {
                size = "100%";
                content = {
                  type = "filesystem";
                  format = "ext4";
                  mountpoint = "/";
                };
              };
            };
          };
        };
      };
  };
}
