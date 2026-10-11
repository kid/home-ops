{
  den,
  config,
  inputs,
  ...
}:
{
  den.hosts.x86_64-linux.node1 = {
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
      imports = [ inputs.sops-nix.nixosModules.sops ];

      boot.loader.systemd-boot.enable = true;
      boot.loader.efi.canTouchEfiVariables = true;

      networking.hostId = lib.mkDefault "795500d2";

      networking.hostName = "node1";
      networking.useDHCP = false;
      networking.useNetworkd = true;

      systemd.network.netdevs = {
        "20-vlan-storage" = {
          netdevConfig = {
            Name = "vlan${toString den.networks.Storage.vlanId}";
            Kind = "vlan";
            MTUBytes = den.networks.Storage.mtu;
          };
          vlanConfig.Id = den.networks.Storage.vlanId;
        };
        "20-br-storage" = {
          netdevConfig = {
            Name = "br-storage";
            Kind = "bridge";
            MTUBytes = den.networks.Storage.mtu;
          };
        };
      };

      systemd.network.networks = {
        "10-trunk" = {
          matchConfig.Name = "enp36s0f1";
          networkConfig.DHCP = "yes";
          linkConfig.MTUBytes = den.networks.Storage.mtu;
          vlan = [ "vlan${toString den.networks.Storage.vlanId}" ];
        };
        # Guest-only L2: no host address here, a second routed interface
        # raced enp36s0f1's default route before (strict rpfilter).
        "20-vlan-storage" = {
          matchConfig.Name = "vlan${toString den.networks.Storage.vlanId}";
          networkConfig = {
            Bridge = "br-storage";
            LinkLocalAddressing = "no";
          };
        };
        "20-br-storage" = {
          matchConfig.Name = "br-storage";
          networkConfig.LinkLocalAddressing = "no";
          linkConfig.RequiredForOnline = "no";
        };
      };

      # impermanence binds /etc/ssh after activation; read the key at its source.
      sops.age.sshKeyPaths = [ "/persist/etc/ssh/ssh_host_ed25519_key" ];
      sops.secrets.k3s-prd-1-ssh-host-key = {
        sopsFile = ../../../secrets/hosts/k3s-prd-1/ssh_host_ed25519_key.sops;
        format = "binary";
        owner = "microvm";
      };

      microvm.autostart = [ "k3s-prd-1" ];
      # Its K3s tap joins the Incus-managed bridge, which incusd creates.
      systemd.services."microvm-tap-interfaces@k3s-prd-1" = {
        overrideStrategy = "asDropin";
        after = [ "incus.service" ];
        wants = [ "incus.service" ];
      };

      time.timeZone = "UTC";
      i18n.defaultLocale = "en_US.UTF-8";

      users.mutableUsers = false;

      system.stateVersion = "26.05";

      environment.systemPackages = [ pkgs.htop ];
    };

  den.aspects.node1.includes = [
    den.aspects.base
    den.aspects.disko.zfs-disk-single
    den.aspects.impermanence
    den.aspects.impermanence.tmpfs
    den.aspects.incus
    den.aspects.microvm-host
    den.aspects.power-saving
    (den.aspects.ssh { addresses = [ config.den.devices.node1.address ]; })
  ];

  fleet.user-access.by-host.node1.groups = [ "admin" ];

  fleet.nh.targets.node1.hostname = config.den.devices.node1.address;
}
