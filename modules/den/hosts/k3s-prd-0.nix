{ den, config, ... }:
{
  den.hosts.x86_64-linux.k3s-prd-0 = {
    k3s.clusterName = "prd";
  };

  den.devices."k3s-prd-0-k3s" = {
    network = "K3s";
    hostNum = 10;
    mac = "52:54:00:40:00:01";
  };

  den.aspects.k3s-prd-0.nixos =
    {
      modulesPath,
      lib,
      pkgs,
      ...
    }:
    {
      imports = [ (modulesPath + "/virtualisation/incus-virtual-machine.nix") ];

      networking.hostName = "k3s-prd-0";
      networking.useDHCP = lib.mkDefault true;
      # Required for ZFS pool import; this host's root disk is a pre-built
      # qemuImage (not a disko install), so this is only for the extra
      # miroir-data disk below.
      networking.hostId = "6b3e8a1f";

      users.mutableUsers = false;

      services.openssh.enable = true;
      services.openssh.generateHostKeys = false;

      services.cloud-init = {
        enable = true;
        settings.datasource_list = [ "NoCloud" ];
      };

      # This VM's root disk comes from config.system.build.qemuImage, baked
      # directly from this config — unlike node1, disko never runs here, so
      # the second (miroir-data) disk Terraform attaches
      # (tf-catalog/modules/incus-k3s) needs its own ZFS pool created by
      # hand on first boot, not via den.aspects.disko.
      boot.supportedFilesystems = [ "zfs" ];
      boot.zfs.extraPools = [ "miroir" ];

      # CONFIRM this by-id path after the first `terraform apply` attaches
      # the disk (Incus VM extra disks get a stable
      # /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_incus_<device-name>-style
      # id) — placeholder until then.
      systemd.services.zfs-pool-miroir-init = {
        description = "Create the miroir ZFS pool on first boot if absent";
        before = [ "zfs-import-miroir.service" ];
        wantedBy = [ "zfs-import-miroir.service" ];
        path = [ pkgs.zfs ];
        serviceConfig.Type = "oneshot";
        script = ''
          zpool list miroir >/dev/null 2>&1 || \
            zpool create -o ashift=12 miroir /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_incus_miroir-data
        '';
      };

      system.stateVersion = "26.05";
    };

  den.aspects.k3s-prd-0.includes = [
    den.aspects.base
    den.aspects.k3s-server
    den.aspects.k3s-cilium
    den.aspects.k3s-bootstrap
    den.aspects.k3s-sops-operator
    den.aspects.k3s-miroir
    (den.aspects.ssh { })
  ];

  fleet.user-access.by-host.k3s-prd-0.groups = [ "admin" ];

  fleet.nh.targets.k3s-prd-0.hostname = config.den.devices."k3s-prd-0-k3s".address;
}
