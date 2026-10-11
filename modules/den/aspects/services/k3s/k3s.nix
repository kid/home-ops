# k3s server aspect. A cluster's only declared server starts embedded etcd
# (clusterInit); once a second server is declared, none does and each points
# at another one. So a cluster has to start with one server: the flag is
# only needed to create the datastore, and a server that already has one
# ignores both settings. CIDRs come from the host's own cluster
# (config.den.clusters.<name>, cross-referenced via the freeform
# host.k3s.clusterName field), matching the cluster entity as the single
# source of truth pattern already used throughout this repo's
# network/device fleet.
#
# Emits the `k3s-nodes` quirk ({hostname; address;}), collected onto
# rb5009 by modules/den/policies/pipes.nix's
# routeros-device-collect-k3s-nodes (consumed by modules/den/aspects/routeros/
# ros-bgp.nix, to build its per-node BGP connections) — `address` is this
# host's primary (first-interface) address from its own den.devices entry,
# which for a k3s host is the K3s VLAN one (see modules/den/hosts/k3s-prd-0.nix).
{
  config,
  den,
  lib,
  ...
}:
let
  clusters = config.den.clusters or { };

  allHosts = lib.foldl' (acc: system: acc // (config.den.hosts.${system} or { })) { } config.systems;

  # A cluster's servers: its member hosts that are not agents
  # (k3s.serverHost) and have a real address. test-vm has none, so it is no
  # one's peer and stays a standalone server.
  serversOf =
    clusterName:
    lib.filter (
      name:
      (allHosts.${name}.k3s.clusterName or null) == clusterName
      && !(allHosts.${name}.k3s ? serverHost)
      && config.den.devices ? ${name}
    ) (lib.sort lib.lessThan (builtins.attrNames allHosts));
in
{
  den.aspects.k3s-server = {
    includes = [
      den.aspects.k3s-containerd
      den.aspects.k3s-node-base
    ];

    k3s-nodes =
      { host, ... }:
      {
        hostname = host.name;
        # null for hosts with no den.devices entry (e.g.
        # test-vm, a throwaway QEMU smoke-test host with no real network
        # attachment) — modules/den/aspects/routeros/bgp.nix filters these
        # out rather than feeding a bogus peer IP to RouterOS.
        address = (config.den.devices.${host.name} or { }).address or null;
        role = "server";
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
        ...
      }:
      let
        clusterName = host.k3s.clusterName or "prd";
        cluster = clusters.${clusterName};
        podCIDR = cluster.networks.pods.cidr;
        serviceCIDR = cluster.networks.services.cidr;
        nodeIp = (config.den.devices.${host.name} or { }).address or null;

        servers = serversOf clusterName;
        peers = lib.optionals (lib.elem host.name servers) (lib.remove host.name servers);
        shouldInit = peers == [ ];
      in
      {
        services.k3s = {
          enable = true;
          role = "server";
          clusterInit = shouldInit;
          serverAddr = lib.mkIf (!shouldInit) "https://${config.den.devices.${lib.head peers}.address}:6443";
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
            "--etcd-expose-metrics"
            "--kube-scheduler-arg=bind-address=0.0.0.0"
            "--kube-controller-manager-arg=bind-address=0.0.0.0"
          ]
          ++ lib.optional (nodeIp != null) "--node-ip=${nodeIp}";
        };
      };
  };
}
