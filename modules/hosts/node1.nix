# node1 — bare-metal box for the `prd` cluster: k3s node, Incus VM host, and
# NFS storage. Installs directly onto real hardware via nixos-anywhere
# (`nix run .#nixos-anywhere-install`, modules/flake/nixos-anywhere.nix).
{ den, config, ... }:
{
  den.hosts.x86_64-linux.node1 = {
    k3s.clusterName = "prd";
    settings.disko.zfs-disk-single.settings.device_id =
      "/dev/disk/by-id/nvme-Force_MP510_21368248000129171009";
  };

  den.devices = {
    node1 = {
      network = "Servers";
      hostNum = 10;
      mac = "d0:50:99:fe:51:b5";
    };
    node1-storage = {
      network = "Storage";
      hostNum = 10;
      mac = "d0:50:99:fe:51:b5";
    };
    node1-k3s = {
      network = "K3s";
      hostNum = 10;
      mac = "d0:50:99:fe:51:b5";
    };
    node1-ipmi = {
      network = "Management";
      hostNum = (den.networks.Servers.vlanId * 256) + 10;
      mac = "d0:50:99:f7:ee:15";
    };
  };

  den.aspects.node1.nixos =
    { lib, pkgs, ... }:
    {
      boot.loader.systemd-boot.enable = true;
      boot.loader.efi.canTouchEfiVariables = true;

      services.k3s.extraFlags = [
        "--node-label=kidibox.net/egress-gateway=true"
      ];

      networking.hostId = lib.mkDefault "795500d2";

      networking.hostName = "node1";
      networking.useDHCP = false;
      networking.useNetworkd = true;

      systemd.network.netdevs = {
        "20-storage" = {
          netdevConfig = {
            Kind = "vlan";
            Name = "storage";
          };
          vlanConfig.Id = den.networks.Storage.vlanId;
        };
        "20-k3s" = {
          netdevConfig = {
            Kind = "vlan";
            Name = "k3s";
          };
          vlanConfig.Id = den.networks.K3s.vlanId;
        };
      };

      systemd.network.networks = {
        "10-trunk" = {
          matchConfig.Name = "enp36s0f1";
          networkConfig.DHCP = "yes";
          vlan = [
            "storage"
            "k3s"
          ];
          linkConfig.MTUBytes = den.networks.Storage.mtu;
        };
        "30-storage" = {
          matchConfig.Name = "storage";
          networkConfig.DHCP = "yes";
          # Keep the Storage subnet route, but don't let it compete with
          # enp36s0f1's default route — three equal-metric default routes
          # make the kernel's reverse-path check pick an arbitrary egress
          # interface, which the firewall's strict rpfilter then treats as
          # spoofed traffic and silently drops.
          dhcpV4Config.UseGateway = false;
          linkConfig.MTUBytes = den.networks.Storage.mtu;
        };
        "30-k3s" = {
          matchConfig.Name = "k3s";
          networkConfig.DHCP = "yes";
          # See "30-storage" above. Cilium's own device (`devices = [ "k3s" ]`
          # in modules/kubernetes/cilium/default.nix) and egress gateway
          # (`interface: k3s` in cilium/egress-gateway.nix) are both
          # hardcoded to this interface already, independent of the host's
          # default route — pod traffic is unaffected by removing this.
          dhcpV4Config.UseGateway = false;
          linkConfig.MTUBytes = 1500;
        };
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
    den.aspects.k3s-server
    den.aspects.k3s-cilium
    den.aspects.k3s-bootstrap
    den.aspects.k3s-openebs
    den.aspects.k3s-miroir
    den.aspects.power-saving
    den.aspects.k3s-sops-operator
    (den.aspects.ssh { addresses = [ config.den.devices.node1.address ]; })
  ];

  # Grants kid's "admin" access-policy group (modules/users/kid.nix) onto
  # this host — see modules/den/policies/users.nix for how this resolves.
  fleet.user-access.by-host.node1.groups = [ "admin" ];

  fleet.nh.targets.node1.hostname = config.den.devices.node1.address;
}
