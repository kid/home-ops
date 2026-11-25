# Empties the root on every boot: rolls zroot/local/root back to the @empty
# snapshot den.aspects.disk.zfs takes at install, after the initrd imports the
# pool and before it mounts /sysroot.
{ den, ... }:
{
  den.aspects.impermanence.rollback-zfs.nixos =
    {
      host,
      config,
      lib,
      ...
    }:
    {
      config =
        lib.mkIf (host.hasAspect den.aspects.disk.zfs && host.settings.impermanence.wipeRootOnBoot)
          {
            boot.initrd.systemd.services.rollback-root = {
              description = "Roll the root dataset back to @empty";
              wantedBy = [ "initrd.target" ];
              requires = [ "zfs-import-zroot.service" ];
              after = [ "zfs-import-zroot.service" ];
              before = [ "sysroot.mount" ];
              path = [ config.boot.zfs.package ];
              unitConfig.DefaultDependencies = "no";
              serviceConfig.Type = "oneshot";
              script = "zfs rollback -r zroot/local/root@empty";
            };
          };
    };
}
