# k3s server (etcd member) for the prd cluster: an Incus VM on node0,
# installed with nixos-anywhere by the tf-stacks/prd/k3s/incus stack, then
# updated with `colmena apply --on k3s-prd-2`.
{ den, config, ... }:
{
  den.hosts.x86_64-linux.k3s-prd-2 = {
    environment = "prd";
    system-access-groups = [ "admins" ];
    k3s.clusterName = "prd";
  };

  den.devices.k3s-prd-2 = {
    interfaces = [
      {
        network = "K3s";
        hostNum = 42;
        mac = "52:54:00:40:00:03";
      }
      {
        network = "Storage";
        hostNum = 42;
        mac = "52:54:00:20:00:03";
      }
    ];
  };

  den.aspects.k3s-prd-2.nixos = {
    networking.hostName = "k3s-prd-2";
    networking.useDHCP = false;

    # nixos-anywhere puts the key from secrets/hosts/k3s-prd-2 in place.
    services.openssh.generateHostKeys = false;
  };

  den.aspects.k3s-prd-2.includes = [
    den.aspects.base
    den.aspects.incus-vm
    den.aspects.k3s-server
    den.aspects.k3s-token
    den.aspects.k3s-cilium
    den.aspects.k3s-oidc
    den.aspects.k3s-miroir-node
  ];

  fleet.colmena.deployment.k3s-prd-2.targetHost = config.den.devices.k3s-prd-2.address;
}
