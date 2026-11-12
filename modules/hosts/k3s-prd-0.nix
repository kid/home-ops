{ den, config, ... }:
{
  den.hosts.x86_64-linux.k3s-prd-0 = {
    environment = "prd";
    system-access-groups = [ "admins" ];
    settings.k3s.clusterName = "prd";
  };

  den.devices.k3s-prd-0 = {
    interfaces = [
      {
        network = "K3s";
        hostNum = 40;
        mac = "52:54:00:40:00:01";
      }
      {
        network = "Storage";
        hostNum = 40;
        mac = "52:54:00:20:00:01";
      }
    ];
  };

  den.aspects.k3s-prd-0.nixos = {
    networking.hostName = "k3s-prd-0";
    networking.useDHCP = false;

    # nixos-anywhere puts the key from secrets/hosts/k3s-prd-0 in place.
    services.openssh.generateHostKeys = false;
  };

  den.aspects.k3s-prd-0.includes = [
    den.aspects.base
    den.aspects.incus-vm
    den.aspects.k3s.server
    den.aspects.k3s.token
    den.aspects.k3s.cilium
    den.aspects.k3s.bootstrap
    den.aspects.k3s.external-secrets
    den.aspects.k3s.miroir-node
    den.aspects.i915-sriov.guest
  ];

  fleet.colmena.deployment.k3s-prd-0.targetHost = config.den.devices.k3s-prd-0.address;
}
