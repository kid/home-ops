# Kernel and tooling every k3s node needs, server or agent, the k3s
# release, graceful node shutdown, and its NICs from its den.devices entry.
{ config, lib, ... }:
{
  den.aspects.k3s-node-base.nixos =
    { host, pkgs, ... }:
    let
      inherit ((config.den.devices.${host.name} or { interfaces = [ ]; })) interfaces;
      unitName = iface: "10-${lib.toLower iface.network}";
      mtuOf = iface: config.den.networks.${iface.network}.mtu;
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

      systemd.network = lib.mkIf (interfaces != [ ]) {
        # Only where the network sets an MTU: a matching .link file replaces
        # 99-default.link, and with it the predictable interface name.
        links =
          interfaces
          |> lib.filter (iface: mtuOf iface != null)
          |> map (
            iface:
            lib.nameValuePair (unitName iface) {
              matchConfig.MACAddress = iface.mac;
              linkConfig.MTUBytes = mtuOf iface;
            }
          )
          |> lib.listToAttrs;
        # Only the first (primary) interface installs the default route.
        networks =
          interfaces
          |> lib.imap0 (
            i: iface:
            lib.nameValuePair (unitName iface) {
              matchConfig.MACAddress = iface.mac;
              networkConfig.DHCP = "yes";
              dhcpV4Config.UseGateway = i == 0;
            }
          )
          |> lib.listToAttrs;
      };
    };
}
