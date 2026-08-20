# k3s server aspect. Single-node only (clusterInit=true unconditionally) —
# multi-node join-token logic is future work, only needed if/when a second
# host joins the `prd` cluster. CIDRs come from the host's own cluster
# (config.den.clusters.<name>, cross-referenced via the freeform
# host.k3s.clusterName field), matching the cluster entity as the single
# source of truth pattern already used throughout this repo's
# network/device fleet.
#
# Emits the `k3s-nodes` quirk ({hostname; address;}), collected onto
# rb5009 by modules/den/policies/pipes.nix's
# routeros-device-collect-k3s-nodes (consumed by modules/network/aspects/
# ros-bgp.nix, to build its per-node BGP connections) — `address` is this
# host's own IP on the K3s VLAN, read from the `<hostname>-k3s` den.devices
# entry every k3s host declares (see modules/hosts/node1.nix).
{
  config,
  den,
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
        # null for hosts with no `<hostname>-k3s` den.devices entry (e.g.
        # test-vm, a throwaway QEMU smoke-test host with no real network
        # attachment) — modules/network/aspects/ros-bgp.nix filters these
        # out rather than feeding a bogus peer IP to RouterOS.
        address = (config.den.devices."${host.name}-k3s" or { }).address or null;
      };

    persist.directories = [
      "/etc/rancher"
      "/var/lib/kubelet"
      "/var/lib/rancher"
    ];

    nixos =
      {
        host,
        lib,
        pkgs,
        ...
      }:
      let
        clusterName = host.k3s.clusterName or "prd";
        cluster = clusters.${clusterName};
        podCIDR = cluster.networks.pods.cidr;
        serviceCIDR = cluster.networks.services.cidr;
        # Pin node-ip to this host's own K3s-VLAN address (same value the
        # k3s-nodes quirk above uses) — hosts here are multi-homed, and
        # k3s's own auto-detection isn't stable across reboots, which
        # breaks etcd (its persisted peer URL stops matching).
        nodeIp = (config.den.devices."${host.name}-k3s" or { }).address or null;
      in
      {
        services.k3s = {
          enable = true;
          role = "server";
          clusterInit = true;
          # CNI-agnostic disables only — CNI-dependent flags live in the
          # sibling den.aspects.k3s-cilium aspect instead. A plain list, not
          # a concatStringsSep string: extraFlags accepts `listOf str`, and
          # multiple aspects setting it concatenate automatically.
          extraFlags = [
            "--disable=coredns"
            "--disable=local-storage"
            "--disable=metrics-server"
            "--cluster-cidr=${podCIDR}"
            "--service-cidr=${serviceCIDR}"
            # Bare path, NOT unix://…: k3s forwards this to the kubelet's
            # legacy cadvisor --containerd flag, which dials it verbatim —
            # with a scheme the dial fails and cadvisor silently falls
            # back, losing per-container metrics. The kubelet normalizes
            # the bare path for CRI itself.
            "--container-runtime-endpoint=/run/containerd/containerd.sock"
          ]
          ++ lib.optional (nodeIp != null) "--node-ip=${nodeIp}";
        };

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
