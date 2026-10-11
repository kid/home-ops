# k3s worker for the prd cluster, a microvm.nix guest on node1. Not in
# node1's closure: install and update it with its own microvm.deploy.*
# scripts (see AGENTS.md).
{
  den,
  config,
  inputs,
  ...
}:
let
  k3sIf = builtins.elemAt config.den.devices.k3s-prd-1.interfaces 0;
  storageIf = builtins.elemAt config.den.devices.k3s-prd-1.interfaces 1;
  k3sGateway = config.den.environments.prd.networks.K3s.methods.host 1;
in
{
  den.hosts.x86_64-linux.k3s-prd-1 = {
    k3s = {
      clusterName = "prd";
      serverHost = "k3s-prd-0";
    };
    microvm.parent = "node1";
    settings.k3s-miroir-node.settings.device = "/dev/disk/by-id/virtio-miroir-data";
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
    { lib, pkgs, ... }:
    {
      imports = [ inputs.microvm.nixosModules.microvm ];

      networking.hostName = "k3s-prd-1";
      networking.useDHCP = false;
      networking.useNetworkd = true;

      # Static: the rb5009 leases for these MACs are generated but not applied.
      systemd.network.networks = {
        "10-k3s" = {
          matchConfig.MACAddress = k3sIf.mac;
          address = [ "${k3sIf.address}/${toString den.networks.K3s.prefix}" ];
          gateway = [ k3sGateway ];
          dns = [ k3sGateway ];
        };
        # No gateway: one default route only.
        "10-storage" = {
          matchConfig.MACAddress = storageIf.mac;
          address = [ "${storageIf.address}/${toString den.networks.Storage.prefix}" ];
          linkConfig.MTUBytes = den.networks.Storage.mtu;
        };
      };

      microvm = {
        hypervisor = "qemu";
        vcpu = 4;
        mem = 8192;

        interfaces = [
          {
            type = "tap";
            id = "mv-prd1-k3s";
            inherit (k3sIf) mac;
            tap.vhost = true;
          }
          {
            type = "tap";
            id = "mv-prd1-sto";
            inherit (storageIf) mac;
            tap.vhost = true;
          }
        ];

        # k3s-prd is the Incus-managed K3s VLAN bridge, br-storage is node1's own.
        binScripts.tap-up = lib.mkAfter ''
          ${lib.getExe' pkgs.iproute2 "ip"} link set dev mv-prd1-k3s master k3s-prd
          ${lib.getExe' pkgs.iproute2 "ip"} link set dev mv-prd1-sto mtu ${toString den.networks.Storage.mtu} master br-storage
        '';

        shares = [
          {
            tag = "ro-store";
            source = "/nix/store";
            mountPoint = "/nix/.ro-store";
            proto = "virtiofs";
          }
        ];

        volumes = [
          {
            image = "var.img";
            label = "var";
            mountPoint = "/var";
            size = 40 * 1024;
          }
          # miroir's LVM-thin device: raw, so no mkfs (autoCreate would add one).
          {
            image = "miroir-data.img";
            serial = "miroir-data";
            mountPoint = null;
            size = 20 * 1024;
            autoCreate = false;
          }
        ];
        preStart = ''
          [ -e miroir-data.img ] || ${lib.getExe' pkgs.coreutils "truncate"} -s 20G miroir-data.img
        '';

        # Decrypted on node1 by sops-nix (modules/den/hosts/node1.nix).
        credentialFiles.ssh-host-key = "/run/secrets/k3s-prd-1-ssh-host-key";
      };

      users.mutableUsers = false;

      services.openssh.generateHostKeys = false;
      systemd.services.install-ssh-host-key = {
        description = "Install the SSH host key passed by the hypervisor";
        wantedBy = [ "multi-user.target" ];
        before = [
          "sshd.service"
          "sops-install-secrets.service"
        ];
        requiredBy = [
          "sshd.service"
          "sops-install-secrets.service"
        ];
        path = [ pkgs.openssh ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ImportCredential = "ssh-host-key";
        };
        script = ''
          install -m 600 "$CREDENTIALS_DIRECTORY/ssh-host-key" /etc/ssh/ssh_host_ed25519_key
          ssh-keygen -y -f /etc/ssh/ssh_host_ed25519_key > /etc/ssh/ssh_host_ed25519_key.pub
        '';
      };
      # The age key only exists after install-ssh-host-key; same ordering
      # problem (and fix) as cloud-init in k3s/external-secrets.nix.
      sops.useSystemdActivation = true;
      systemd.services.sops-install-secrets = {
        wantedBy = lib.mkForce [ "multi-user.target" ];
        before = lib.mkForce [ ];
      };

      # The root is a tmpfs; only /var is a disk.
      environment.etc."machine-id".text = builtins.hashString "md5" "k3s-prd-1" + "\n";
      systemd.tmpfiles.rules = [
        "d /var/lib/etc-rancher 0755 root root -"
        "L+ /etc/rancher - - - - /var/lib/etc-rancher"
      ];

      system.stateVersion = "26.05";
    };

  den.aspects.k3s-prd-1.includes = [
    den.aspects.base
    den.aspects.k3s-agent
    den.aspects.k3s-cilium
    den.aspects.k3s-miroir
    den.aspects.k3s-miroir-node
    (den.aspects.ssh { })
  ];

  fleet.user-access.by-host.k3s-prd-1.groups = [ "admin" ];
}
