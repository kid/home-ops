# Kernel and tooling every k3s node needs, server or agent.
_: {
  den.aspects.k3s-node-base.nixos =
    { pkgs, ... }:
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
    };
}
