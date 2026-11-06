# Kernel and tooling every k3s node needs, server or agent, the k3s
# release, graceful node shutdown, and the MTU of its Storage VLAN NIC (if its
# den.devices entry has one).
{ config, lib, ... }:
{
  den.aspects.k3s-node-base.nixos =
    { host, pkgs, ... }:
    let
      storage =
        lib.findFirst (i: i.network == "Storage") null
          (config.den.devices.${host.name} or { interfaces = [ ]; }).interfaces;
      # Seconds; the Incus host's own timeout for the VMs must exceed it.
      shutdownGracePeriod = 120;
    in
    {
      # 1.37 enables HPAScaleToZero, which cluster.methods.mkNfsScaler needs.
      services.k3s.package = pkgs.k3s_1_37;

      # On a reboot or poweroff the kubelet stops pods first (regular ones,
      # then critical ones in the last 30s), so the apps close their SQLite
      # databases and NFS mounts are released before the network goes down.
      services.k3s.extraFlags = [
        "--kubelet-arg=shutdown-grace-period=${toString shutdownGracePeriod}s"
        "--kubelet-arg=shutdown-grace-period-critical-pods=30s"
      ];
      # The kubelet holds its delay through a logind inhibitor lock, which
      # logind caps at this (5s by default).
      services.logind.settings.Login.InhibitDelayMaxSec = shutdownGracePeriod;

      boot.kernelModules = [
        "br_netfilter"
        "overlay"
        "ip_vs"
        "ip_vs_rr"
        "ip_vs_wrr"
        "ip_vs_sh"
      ];
      boot.kernel.sysctl = {
        "net.bridge.bridge-nf-call-iptables" = 1;
        "net.bridge.bridge-nf-call-ip6tables" = 1;
        "net.core.bpf_jit_enable" = 1;
        "net.core.bpf_jit_harden" = 0;
      };

      # mount.nfs for the kubelet's NFS volumes.
      boot.supportedFilesystems = [ "nfs" ];

      environment.systemPackages = [
        pkgs.iptables
        pkgs.nftables
      ];

      systemd.network.links = lib.mkIf (storage != null) {
        "10-storage" = {
          matchConfig.MACAddress = storage.mac;
          linkConfig.MTUBytes = config.den.networks.Storage.mtu;
        };
      };
    };
}
