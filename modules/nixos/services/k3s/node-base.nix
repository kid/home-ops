# Kernel and tooling every k3s node needs, server or agent, and the MTU of
# its Storage VLAN NIC (if its den.devices entry has one).
{ config, lib, ... }:
{
  den.aspects.k3s-node-base.nixos =
    { host, pkgs, ... }:
    let
      storage =
        lib.findFirst (i: i.network == "Storage") null
          (config.den.devices.${host.name} or { interfaces = [ ]; }).interfaces;
    in
    {
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
