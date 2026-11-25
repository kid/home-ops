# Empties the root on every boot: deletes and recreates den.aspects.disk.btrfs'
# root subvolume once the initrd sees the disk and before it mounts /sysroot.
{ den, ... }:
{
  den.aspects.impermanence.rollback-btrfs.nixos =
    { host, lib, ... }:
    let
      cfg = host.settings.disk.btrfs;
      root = lib.removePrefix "/" "${cfg.subvolumePrefix}root";
    in
    {
      config =
        lib.mkIf (host.hasAspect den.aspects.disk.btrfs && host.settings.impermanence.wipeRootOnBoot)
          {
            # Root gets nested subvolumes (systemd-tmpfiles' srv, var/lib/{machines,portables},
            # tmp, var/tmp, ...) that a plain delete refuses with ENOTEMPTY.
            boot.initrd.systemd.services.rollback-root = {
              description = "Recreate the root subvolume empty";
              wantedBy = [ "initrd.target" ];
              after = [ "initrd-root-device.target" ];
              before = [ "sysroot.mount" ];
              unitConfig.DefaultDependencies = "no";
              serviceConfig.Type = "oneshot";
              script = ''
                mkdir -p /mnt
                mount -t btrfs -o subvolid=5 /dev/disk/by-partlabel/disk-main-${cfg.partitionName} /mnt
                btrfs subvolume delete --recursive /mnt/${root}
                btrfs subvolume create /mnt/${root}
                umount /mnt
              '';
            };
          };
    };
}
