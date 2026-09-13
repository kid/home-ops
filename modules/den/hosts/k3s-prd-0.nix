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
    { modulesPath, lib, ... }:
    {
      imports = [ (modulesPath + "/virtualisation/incus-virtual-machine.nix") ];

      networking.hostName = "k3s-prd-0";
      networking.useDHCP = lib.mkDefault true;

      users.mutableUsers = false;

      services.openssh.enable = true;
      services.openssh.generateHostKeys = false;

      services.cloud-init = {
        enable = true;
        settings.datasource_list = [ "NoCloud" ];
      };

      system.stateVersion = "26.05";
    };

  den.aspects.k3s-prd-0.includes = [
    den.aspects.base
    den.aspects.k3s-server
    den.aspects.k3s-cilium
    den.aspects.k3s-bootstrap
    den.aspects.k3s-sops-operator
    (den.aspects.ssh { })
  ];

  fleet.user-access.by-host.k3s-prd-0.groups = [ "admin" ];

  fleet.nh.targets.k3s-prd-0.hostname = config.den.devices."k3s-prd-0-k3s".address;
}
