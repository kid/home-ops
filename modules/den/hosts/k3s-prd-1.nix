# k3s worker for the prd cluster: an Incus VM on node1, installed with
# nixos-anywhere by the tf-stacks/prd/k3s/incus stack, then updated with
# `deploy k3s-prd-1`.
{ den, config, ... }:
{
  den.hosts.x86_64-linux.k3s-prd-1 = {
    k3s = {
      clusterName = "prd";
      serverHost = "k3s-prd-0";
    };
    settings.k3s-miroir-node.settings.device = "/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_incus_miroir--data";
    settings.disko.vm-ext4.settings.device = "/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_incus_root";
  };

  den.devices.k3s-prd-1 = {
    interfaces = [
      {
        network = "K3s";
        hostNum = 11;
        mac = "52:54:00:40:00:02";
      }
      {
        network = "Storage";
        hostNum = 11;
        mac = "52:54:00:20:00:02";
      }
    ];
  };

  den.aspects.k3s-prd-1.nixos =
    { modulesPath, ... }:
    {
      imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

      boot.loader.systemd-boot.enable = true;
      boot.loader.efi.canTouchEfiVariables = true;

      virtualisation.incus.agent.enable = true;

      networking.hostName = "k3s-prd-1";
      # Both NICs: the Storage DHCP server sends no gateway.
      networking.useDHCP = true;

      users.mutableUsers = false;

      # nixos-anywhere puts the key from secrets/hosts/k3s-prd-1 in place.
      services.openssh.generateHostKeys = false;

      system.stateVersion = "26.05";
    };

  den.aspects.k3s-prd-1.includes = [
    den.aspects.base
    den.aspects.disko.vm-ext4
    den.aspects.k3s-agent
    den.aspects.k3s-cilium
    den.aspects.k3s-miroir-node
    den.aspects.ssh
  ];

  fleet.user-access.by-host.k3s-prd-1.groups = [ "admin" ];

  fleet.nh.targets.k3s-prd-1.hostname = config.den.devices.k3s-prd-1.address;
}
