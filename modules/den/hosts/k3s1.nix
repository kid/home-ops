# Throwaway Incus VM, not real hardware or the home network. Built as a
# bootable qcow2 + metadata tarball via nixpkgs' own
# incus-virtual-machine.nix module, not disko/nixos-anywhere:
#   nix build .#nixosConfigurations.k3s1.config.system.build.qemuImage
#   nix build .#nixosConfigurations.k3s1.config.system.build.metadata
#
# No k3s-cilium: k3s-server's default flannel CNI + kube-proxy is enough
# for the dev cluster's app set (cert-manager/coredns/argocd/sops-operator,
# see modules/den/clusters/dev.nix); k3s-bootstrap's cilium wave skips
# itself when host.hasAspect den.aspects.k3s-cilium is false.
{ den, ... }:
{
  den.hosts.x86_64-linux.k3s1 = {
    k3s.clusterName = "dev";
  };

  den.aspects.k3s1.nixos =
    { modulesPath, lib, ... }:
    {
      imports = [ (modulesPath + "/virtualisation/incus-virtual-machine.nix") ];

      networking.hostName = "k3s1";
      networking.useDHCP = lib.mkDefault true;

      users.mutableUsers = false;
      # Throwaway box, console-only: fixed known password for smoke-testing.
      users.users.root.initialPassword = "root";
      security.sudo.enable = true;
      security.sudo.wheelNeedsPassword = false;

      services.openssh.enable = true;

      # Real host key delivered via Incus's cloud-init NoCloud seed disk
      # (tf-stacks/dev/compute/incus-k3s), not a first-boot keygen. The
      # "ssh" cc-module that applies it runs in cloud-init's modules:config
      # stage (cloud-config.service), which has no ordering against sshd by
      # default — force it, or sshd binds with a throwaway key first.
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

  den.aspects.k3s1.includes = [
    den.aspects.k3s-server
    den.aspects.k3s-bootstrap
    den.aspects.k3s-sops-operator
  ];

  fleet.user-access.by-host.k3s1.groups = [ "admin" ];
}
