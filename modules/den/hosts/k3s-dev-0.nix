{ den, ... }:
{
  den.hosts.x86_64-linux.k3s-dev-0 = {
    k3s.clusterName = "dev";
  };

  den.aspects.k3s-dev-0.nixos =
    { modulesPath, lib, ... }:
    {
      imports = [ (modulesPath + "/virtualisation/incus-virtual-machine.nix") ];

      networking.hostName = "k3s-dev-0";
      networking.useDHCP = lib.mkDefault true;

      users.mutableUsers = false;
      users.users.root.initialPassword = "root";
      security.sudo.enable = true;
      security.sudo.wheelNeedsPassword = false;

      services.openssh.enable = true;

      services.k3s.extraFlags = [ "--disable=traefik" ];

      services.cloud-init = {
        enable = true;
        settings.datasource_list = [ "NoCloud" ];
      };
      systemd.services.sshd = {
        after = [ "cloud-config.service" ];
        wants = [ "cloud-config.service" ];
      };

      system.stateVersion = "26.05";
    };

  den.aspects.k3s-dev-0.includes = [
    den.aspects.k3s-server
    den.aspects.k3s-bootstrap
    den.aspects.k3s-sops-operator
  ];

  fleet.user-access.by-host.k3s-dev-0.groups = [ "admin" ];
}
