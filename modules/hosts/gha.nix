# GitHub Actions runner VM on node0, alone on the CI VLAN. Declares its own
# Incus VM (tf-stacks/prd/hosts/gha/incus), installed by nixos-anywhere, then
# updated with `colmena apply --on gha`. A routed nix builder client
# (modules/nixos/services/nix-builders.nix): builds run on the builders.
{
  den,
  config,
  lib,
  ...
}:
{
  den.hosts.x86_64-linux.gha = {
    environment = "prd";
    system-access-groups = [ "admins" ];
    nix-builder-client.routed = true;
  };

  den.devices.gha.interfaces = [
    {
      network = "CI";
      hostNum = 10;
      mac = "52:54:00:30:00:01";
    }
  ];

  den.aspects.gha = {
    nixos = {
      networking.hostName = "gha";
      networking.useDHCP = false;

      # nixos-anywhere puts the key from secrets/hosts/gha in place.
      services.openssh.generateHostKeys = false;

      # No miroir on this VM: the root LV takes the whole VG.
      disko.devices.lvm_vg.vg-miroir.lvs.root.size = lib.mkForce "100%FREE";
    };

    "terragrunt-stacks" =
      { host, ... }:
      {
        stack = "incus";
        localModule = "incus-nixos-vm";
        generate = {
          label = "incus_provider";
          path = "incus_provider.tf";
          ifExists = "overwrite_terragrunt";
          contents = ''
            provider "incus" {
              default_remote = "node0"

              remote {
                name    = "node0"
                address = "https://${config.den.devices.node0.address}:8443"
              }

              remote {
                name     = "images"
                address  = "https://images.linuxcontainers.org"
                protocol = "simplestreams"
              }
            }
          '';
        };
        inputs = {
          inherit (host) name;
          remote = "node0";
          nixos_attr = host.name;
          cpu = 4;
          memory = "6GiB";
          disk_size = "100GiB";
          inherit (config.den.devices.${host.name}) address;
          inherit (builtins.head config.den.devices.${host.name}.interfaces) mac;
          bridge = "ci-prd";
          storage_pool = "default";
          ssh_authorized_keys =
            config.den.users.registry
            |> lib.attrValues
            |> lib.concatMap (u: u.sshKeys)
            |> lib.unique;
        };
      };

    includes = [
      den.aspects.base
      den.aspects.incus-vm
      den.aspects.github-runner
    ];
  };

  fleet.colmena.deployment.gha.targetHost = config.den.devices.gha.address;
}
