{ den, config, ... }:
{
  den.hosts.x86_64-linux.node1 = {
    environment = "prd";
    system-access-groups = [ "admins" ];
    settings.disko.zfs-disk-single.settings.device_id =
      "/dev/disk/by-id/nvme-Force_MP510_21368248000129171009";
  };

  den.devices = {
    node1 = {
      interfaces = [
        {
          network = "Servers";
          hostNum = 10;
          mac = "d0:50:99:fe:51:b5";
        }
      ];
    };
    node1-ipmi = {
      interfaces = [
        {
          network = "Management";
          hostNum = (den.networks.Servers.vlanId * 256) + 10;
          mac = "d0:50:99:f7:ee:15";
        }
      ];
    };
  };

  den.aspects.node1.nixos =
    { lib, pkgs, ... }:
    {
      boot.loader.systemd-boot.enable = true;
      boot.loader.efi.canTouchEfiVariables = true;

      # IPMI Serial-over-LAN (`ipmitool sol activate`). The last console=
      # is the one systemd puts a serial getty on.
      boot.kernelParams = [
        "console=tty0"
        "console=ttyS1,115200n8"
      ];

      networking.hostId = lib.mkDefault "795500d2";

      networking.hostName = "node1";
      networking.useDHCP = false;
      networking.useNetworkd = true;

      systemd.network.networks = {
        "10-trunk" = {
          matchConfig.Name = "enp36s0f1";
          networkConfig.DHCP = "yes";
          linkConfig.MTUBytes = den.networks.Storage.mtu;
        };
      };

      time.timeZone = "UTC";
      i18n.defaultLocale = "en_US.UTF-8";

      users.mutableUsers = false;

      # ZFS only. LVM would otherwise scan the Incus zvols and try to
      # activate the volume groups the guests created on them.
      services.lvm.enable = false;

      system.stateVersion = "26.05";

      environment.systemPackages = [ pkgs.htop ];
    };

  den.aspects.node1.includes = [
    den.aspects.base
    den.aspects.disko.zfs-disk-single
    den.aspects.impermanence
    den.aspects.impermanence.tmpfs
    den.aspects.incus
    den.aspects.power-saving
    den.aspects.ssh
  ];

  fleet.colmena.deployment.node1 = {
    targetHost = config.den.devices.node1.address;
    # Not a k3s node; it hosts the prd k3s VMs.
    tags = [ "incus-host" ];
  };
}
