{
  den,
  config,
  inputs,
  ...
}:
{
  den.hosts.x86_64-linux.node1 = {
    environment = "prd";
    system-access-groups = [ "admins" ];
    settings.disk.zfs.device = "/dev/disk/by-id/nvme-Force_MP510_21368248000129171009";
    settings.k3s.clusterName = "dev";
  };

  den.devices = {
    node1 = {
      # One NIC: K3sDev native, Storage tagged for NFS to node0 (same L2,
      # no router hop).
      interfaces = [
        {
          network = "K3sDev";
          hostNum = 11;
          mac = "d0:50:99:fe:51:b5";
          # The NIC's own MTU: a VLAN can't exceed its parent's, and the
          # tagged Storage VLAN is jumbo.
          inherit (den.networks.Storage) mtu;
        }
        {
          network = "Storage";
          hostNum = 11;
          mac = "d0:50:99:fe:51:b5";
          tagged = true;
        }
      ];
    };
    node1-ipmi = {
      interfaces = [
        {
          network = "Management";
          hostNum = (den.networks.Servers.vlanId * 256) + 11;
          mac = "d0:50:99:f7:ee:15";
        }
      ];
    };
  };

  den.aspects.node1.nixos = {
    imports = [ inputs.srvos.nixosModules.mixins-latest-zfs-kernel ];

    boot.loader.efi.canTouchEfiVariables = true;
    hardware.enableRedistributableFirmware = true;
    hardware.cpu.amd.updateMicrocode = true;

    # IPMI Serial-over-LAN (`ipmitool sol activate`). The last console=
    # is the one systemd puts a serial getty on.
    srvos.boot.consoles = [
      "tty0"
      "ttyS1,115200n8"
    ];

    # The pool's hostid; srvos's mkDefault would need a force import.
    networking.hostId = "795500d2";

    networking.hostName = "node1";
    networking.useDHCP = false;

    i18n.defaultLocale = "en_US.UTF-8";

    # zroot opts out of com.sun:auto-snapshot anyway, and the containerd zfs
    # snapshotter's datasets must never carry snapshots of their own.
    services.zfs.autoSnapshot.enable = false;
  };

  # The dev cluster's only server (modules/clusters/dev.nix), on sqlite.
  den.aspects.node1.includes = [
    den.aspects.base
    den.aspects.disk.zfs
    den.aspects.impermanence
    den.aspects.power-saving
    den.aspects.k3s.server
    den.aspects.k3s.token
    den.aspects.k3s.cilium
    den.aspects.k3s.bootstrap
    den.aspects.k3s.external-secrets
    den.aspects.k3s.zfs-localpv-node
  ];

  fleet.colmena.deployment.node1.targetHost = config.den.devices.node1.address;
}
