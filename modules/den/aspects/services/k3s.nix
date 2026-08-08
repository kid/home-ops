# k3s server aspect. Ported verbatim from nixopslab's
# modules/den/aspects/services/k3s.nix. Single-node only (clusterInit=true
# unconditionally) — multi-node join-token logic is future work, only
# needed if/when a second host joins the `prd` cluster (see plan decision
# #5). CIDRs come from the host's own cluster (config.den.clusters.<name>,
# cross-referenced via the freeform host.k3s.clusterName field), matching
# the cluster entity as the single source of truth pattern already used
# throughout this repo's network/device fleet.
#
# Emits the `k3s-nodes` quirk ({hostname; localASN;}), collected cluster-side
# by modules/den/policies/pipes.nix's cluster-collect-k3s-nodes — consumed
# once modules/kubernetes/cilium/bgp.nix lands (Phase 5).
{
  config,
  den,
  lib,
  ...
}:
let
  clusters = config.den.clusters or { };
in
{
  den.aspects.k3s-server = {
    includes = [ den.aspects.k3s-containerd ];

    k3s-nodes =
      { host, ... }:
      {
        hostname = host.name;
        localASN = host.bgp.localAsn or null;
      };

    persist.directories = [
      "/etc/rancher"
      "/var/lib/kubelet"
      "/var/lib/rancher"
    ];

    nixos =
      { host, pkgs, ... }:
      let
        clusterName = host.k3s.clusterName or "prd";
        cluster = clusters.${clusterName};
        podCIDR = cluster.networks.pods.cidr;
        serviceCIDR = cluster.networks.services.cidr;
      in
      {
        services.k3s = {
          enable = true;
          role = "server";
          clusterInit = true;
          extraFlags = lib.concatStringsSep " " [
            "--flannel-backend=none"
            "--disable-network-policy"
            "--disable-kube-proxy"
            "--disable=coredns"
            "--disable=local-storage"
            "--cluster-cidr=${podCIDR}"
            "--service-cidr=${serviceCIDR}"
            # Bare path, NOT unix://…: k3s forwards this to the kubelet's
            # legacy cadvisor --containerd flag, which dials it verbatim —
            # with a scheme the dial fails and cadvisor silently falls
            # back, losing per-container metrics. The kubelet normalizes
            # the bare path for CRI itself.
            "--container-runtime-endpoint=/run/containerd/containerd.sock"
          ];
        };

        # Cilium's own BPF datapath replaces k3s's default firewall/kube-proxy
        # setup; k3s's iptables must speak nft to match Cilium's nftables use.
        networking.firewall.enable = lib.mkForce false;
        networking.nftables.enable = true;

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
  };
}
