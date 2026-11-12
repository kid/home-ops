# k3s server aspect. den.clusters.<name>.k3s.datastore = "sqlite": the
# cluster's only server runs on k3s's default SQLite datastore (no
# clusterInit, no etcd flags), and a second server is an evaluation error.
# Otherwise, which server starts embedded etcd (clusterInit):
#
# - den.clusters.<name>.k3s.initServer set: that server, and every other one
#   joins it. All servers can be declared and started together, so the
#   cluster can be wiped and recreated with no config change. A rebuilt
#   initServer creates a new cluster instead of rejoining a surviving one —
#   only rebuild it together with the others.
# - unset: a cluster's only declared server; once a second one is declared,
#   none does and each points at another one, so the cluster has to start
#   with one server.
#
# A server that already has a datastore ignores both settings. CIDRs come
# from the host's own cluster
# (config.den.clusters.<name>, named by its `settings.k3s.clusterName`,
# see settings.nix), matching the cluster entity as the single
# source of truth pattern already used throughout this repo's
# network/device fleet. A cluster that includes den.aspects.kubernetes.apiserver
# gets its API server's Kanidm login (kubectl through kubelogin), from its
# methods.kubeLogin.
#
# Emits the `k3s-nodes` quirk ({hostname; address; role; cluster;}), collected onto
# rb5009 by modules/den/policies/pipes.nix's
# routeros-device-collect-k3s-nodes (consumed by modules/routeros/
# ros-bgp.nix, to build its per-node BGP connections) — `address` is this
# host's primary (first-interface) address from its own den.devices entry,
# which for a k3s host is the K3s VLAN one (see modules/hosts/k3s-prd-0.nix).
{
  config,
  den,
  lib,
  ...
}:
let
  clusters = config.den.clusters or { };

  allHosts = lib.foldl' (acc: system: acc // (config.den.hosts.${system} or { })) { } config.systems;

  # A cluster's servers: its k3s nodes that are not agents and have a real
  # address. test-vm has none, so it is no one's peer and stays a
  # standalone server.
  serversOf =
    clusterName:
    allHosts
    |> builtins.attrNames
    |> lib.sort lib.lessThan
    |> lib.filter (
      name:
      let
        host = allHosts.${name};
      in
      host.hasAspect den.aspects.k3s.node-base
      && !(host.hasAspect den.aspects.k3s.agent)
      && host.settings.k3s.clusterName == clusterName
      && config.den.devices ? ${name}
    );
in
{
  den.aspects.k3s.server = {
    includes = [
      den.aspects.k3s.containerd
      den.aspects.k3s.node-base
    ];

    k3s-nodes =
      { host, ... }:
      {
        hostname = host.name;
        # null for hosts with no den.devices entry (e.g.
        # test-vm, a throwaway QEMU smoke-test host with no real network
        # attachment) — modules/routeros/bgp.nix filters these
        # out rather than feeding a bogus peer IP to RouterOS.
        address = (config.den.devices.${host.name} or { }).address or null;
        role = "server";
        cluster = host.settings.k3s.clusterName;
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
        inherit (host.settings.k3s) clusterName;
        cluster = clusters.${clusterName};
        podCIDR = cluster.networks.pods.cidr;
        serviceCIDR = cluster.networks.services.cidr;
        nodeIp = (config.den.devices.${host.name} or { }).address or null;
        login =
          if cluster.includesAspect den.aspects.kubernetes.apiserver then cluster.methods.kubeLogin else null;
        etcd = cluster.k3s.datastore == "etcd";

        servers = serversOf clusterName;
        peers = lib.optionals (lib.elem host.name servers) (lib.remove host.name servers);
        initServer = if lib.elem cluster.k3s.initServer peers then cluster.k3s.initServer else null;
        shouldInit = etcd && (peers == [ ] || cluster.k3s.initServer == host.name);
        joinServer = if initServer != null then initServer else lib.head peers;
      in
      {
        assertions = [
          {
            assertion = cluster.k3s.initServer == null || lib.elem cluster.k3s.initServer servers;
            message = "den.clusters.${clusterName}.k3s.initServer (${toString cluster.k3s.initServer}) is not one of the cluster's servers: ${lib.concatStringsSep ", " servers}";
          }
          {
            assertion = etcd || (servers == [ host.name ] && cluster.k3s.initServer == null);
            message = "den.clusters.${clusterName}.k3s.datastore is sqlite, which allows exactly one server and no initServer; servers: ${lib.concatStringsSep ", " servers}";
          }
        ];

        services.k3s = {
          enable = true;
          role = "server";
          clusterInit = shouldInit;
          serverAddr =
            lib.mkIf (etcd && !shouldInit)
              "https://${config.den.devices.${joinServer}.address}:6443";
          # CNI-agnostic disables only — CNI-dependent flags live in the
          # sibling den.aspects.k3s.cilium aspect instead. A plain list, not
          # a concatStringsSep string: extraFlags accepts `listOf str`, and
          # multiple aspects setting it concatenate automatically.
          extraFlags = [
            "--disable=coredns"
            "--disable=local-storage"
            "--disable=metrics-server"
            # Flux installs the Gateway API CRDs (modules/kubernetes/envoy-gateway/gateway-api-crds.nix).
            # k3s's own chart would take them over with --force-conflicts.
            "--disable=gateway-api-crd"
            "--cluster-cidr=${podCIDR}"
            "--service-cidr=${serviceCIDR}"
            # Bare path, NOT unix://…: k3s forwards this to the kubelet's
            # legacy cadvisor --containerd flag, which dials it verbatim —
            # with a scheme the dial fails and cadvisor silently falls
            # back, losing per-container metrics. The kubelet normalizes
            # the bare path for CRI itself.
            "--container-runtime-endpoint=/run/containerd/containerd.sock"
          ]
          ++ lib.optional etcd "--etcd-expose-metrics"
          ++ [
            "--kube-scheduler-arg=bind-address=0.0.0.0"
            "--kube-controller-manager-arg=bind-address=0.0.0.0"
          ]
          ++ lib.optional (nodeIp != null) "--node-ip=${nodeIp}"
          # A cluster's only server runs the only copy of each: their lease
          # renewals (every 2s each) were most of etcd's writes. A second
          # declared server turns leader election back on.
          ++ lib.optionals (servers == [ host.name ]) [
            "--kube-controller-manager-arg=leader-elect=false"
            "--kube-scheduler-arg=leader-elect=false"
            "--kube-cloud-controller-manager-arg=leader-elect=false"
          ]
          ++ lib.optionals (login != null) [
            # Adds the load balancer name from kubernetes/apiserver/default.nix to the serving certificate.
            "--tls-san=${login.server}"
            "--kube-apiserver-arg=oidc-issuer-url=${login.issuerUrl}"
            "--kube-apiserver-arg=oidc-client-id=${login.clientId}"
            "--kube-apiserver-arg=oidc-groups-claim=groups"
            # Without these the username is "<issuer>#<sub>", an opaque UUID. The prefix keeps OIDC
            # names apart from built-in ones (system:*); RBAC binds the group, not the user.
            "--kube-apiserver-arg=oidc-username-claim=preferred_username"
            "--kube-apiserver-arg=oidc-username-prefix=oidc:"
            # Kanidm signs ID tokens with ES256; kube-apiserver only accepts RS256 by default.
            "--kube-apiserver-arg=oidc-signing-algs=ES256"
          ];
        };
      };
  };
}
