# A vlagent relay for the journals of the hosts outside the cluster
# (modules/nixos/services/log-shipping.nix): unlike vlsingle's port, it
# accepts nothing but ingestion, and buffers while vlsingle restarts. Served
# on the fixed LoadBalancer IP the hosts read from
# cluster.networks.loadBalancer.assignments.vlagent-hosts, with
# externalTrafficPolicy Local so the policy below sees the hosts' own
# addresses rather than a node's.
_: {
  den.aspects.kubernetes.vlagent-hosts.k8s-manifests =
    {
      cluster,
      config,
      lib,
      log-shippers ? [ ],
      ...
    }:
    let
      name = "hosts";
      port = 9429;
      labels = {
        "app.kubernetes.io/name" = "vlagent";
        "app.kubernetes.io/instance" = name;
      };

      # The chart's own vlagent's, so both move together.
      chartTag =
        (lib.findFirst (o: o.kind == "VLAgent") (throw "the chart's VLAgent not rendered")
          config.applications.victoria-metrics.helm.releases.victoria-metrics.objects
        ).spec.image.tag;
    in
    {
      applications.victoria-metrics = {
        resources.vlAgents.${name}.spec = {
          image.tag = chartTag;
          port = toString port;
          remoteWrite = [
            { url = "http://vlsingle-victoria-metrics.monitoring.svc.cluster.local.:9428/insert/native"; }
          ];
          resources = {
            requests = {
              cpu = "10m";
              memory = "32Mi";
            };
            limits.memory = "128Mi";
          };
        };

        resources.services."vlagent-${name}-ingest" = {
          metadata.annotations."lbipam.cilium.io/ips" =
            cluster.networks.loadBalancer.assignments.vlagent-hosts;
          spec = {
            type = "LoadBalancer";
            externalTrafficPolicy = "Local";
            selector = labels;
            ports = [
              {
                name = "http";
                inherit port;
                targetPort = port;
                protocol = "TCP";
              }
            ];
          };
        };

        resources.ciliumNetworkPolicies."vlagent-${name}" = cluster.methods.netpol.mkPolicy labels {
          ingress = [
            {
              fromCIDR = map (s: "${s.address}/32") log-shippers;
              toPorts = cluster.methods.netpol.tcp [ port ];
            }
          ];
        };
      };
    };
}
