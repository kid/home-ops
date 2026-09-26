_: {
  den.aspects.kubernetes.victoria-metrics.k8s-manifests =
    { charts, cluster, ... }:
    let
      mkRoute = hostname: {
        enabled = true;
        parentRefs = [
          {
            group = "gateway.networking.k8s.io";
            kind = "Gateway";
            name = "apps";
            namespace = "envoy-gateway-system";
            sectionName = "https";
          }
        ];
        hostnames = [ hostname ];
      };
    in
    {
      applications.victoria-metrics = {
        namespace = "monitoring";
        createNamespace = true;

        helm.releases.victoria-metrics = {
          chart = charts.victoriametrics.victoria-metrics-k8s-stack;
          values = {
            # Dashboards come from the Grafana Operator (grafana-operator/default.nix) instead.
            grafana.enabled = false;

            victoria-metrics-operator.admissionWebhooks.certManager.enabled = true;

            vmsingle = {
              spec = {
                retentionPeriod = "30d";
                # 20Gi default won't fit alongside vlsingle on the 20GiB miroir-data disk.
                storage.resources.requests.storage = "5Gi";
              };
              route = mkRoute (cluster.methods.mkAppHostname "metrics");
            };

            # The chart natively supports VictoriaLogs alongside VictoriaMetrics
            # in the same release; both default to disabled.
            vlsingle = {
              enabled = true;
              spec = {
                retentionPeriod = "30d";
                storage.resources.requests.storage = "5Gi";
              };
              route = mkRoute (cluster.methods.mkAppHostname "logs");
            };

            # vlagent: VictoriaMetrics's own log collector, ships pod logs
            # straight to the vlsingle this same release creates.
            vlagent.enabled = true;
          };
        };

        # VMUI and VictoriaLogs' own UI have no login of their own — HTTPRoute
        # names below match the chart's own naming (see the rendered
        # HTTPRoute-*.yaml under manifests/prd/victoria-metrics/). `//` merges
        # the two calls' distinct securityPolicies keys, not the outer attrset.
        resources.securityPolicies =
          (cluster.methods.mkForwardAuth {
            name = "vmsingle";
            httpRouteName = "vmsingle-victoria-metrics-victoria-metrics-k8s-stack";
          }).securityPolicies
          // (cluster.methods.mkForwardAuth {
            name = "vlsingle";
            httpRouteName = "vlsingle-victoria-metrics-victoria-metrics-k8s-stack";
          }).securityPolicies;
      };
    };
}
