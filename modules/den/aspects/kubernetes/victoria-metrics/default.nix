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

        helm.releases.victoria-metrics = {
          chart = charts.victoriametrics.victoria-metrics-k8s-stack;
          values = {
            grafana.enabled = false;

            # Release name "victoria-metrics" + chart name "victoria-metrics-k8s-stack"
            # doubles up in every generated resource name by default, and
            # vmalertmanager's StatefulSet then can't create pods: the
            # pod-template-hash label exceeds Kubernetes' 63-byte limit.
            fullnameOverride = "victoria-metrics";

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
            httpRouteName = "vmsingle-victoria-metrics";
          }).securityPolicies
          // (cluster.methods.mkForwardAuth {
            name = "vlsingle";
            httpRouteName = "vlsingle-victoria-metrics";
          }).securityPolicies;

        resources.grafanaDatasources.victoria-metrics.spec = {
          instanceSelector.matchLabels.dashboards = "grafana";
          datasource = {
            name = "VictoriaMetrics";
            type = "victoriametrics-metrics-datasource";
            access = "proxy";
            url = "http://vmsingle-victoria-metrics.monitoring.svc:8428";
            isDefault = true;
          };
        };

        resources.grafanaDatasources.victoria-logs.spec = {
          instanceSelector.matchLabels.dashboards = "grafana";
          datasource = {
            name = "VictoriaLogs";
            type = "victoriametrics-logs-datasource";
            access = "proxy";
            url = "http://vlsingle-victoria-metrics.monitoring.svc:9428";
          };
        };

        resources.grafanaDashboards =
          let
            mkDashboard = url: {
              spec = {
                instanceSelector.matchLabels.dashboards = "grafana";
                inherit url;
              };
            };
            # renovate: datasource=github-releases depName=VictoriaMetrics/VictoriaMetrics
            vmRef = "v1.152.0";
            # renovate: datasource=github-releases depName=VictoriaMetrics/VictoriaLogs
            vlRef = "v1.52.0";
            vmDashboard =
              name:
              mkDashboard "https://raw.githubusercontent.com/VictoriaMetrics/VictoriaMetrics/${vmRef}/dashboards/vm/${name}.json";
            vlDashboard =
              path:
              mkDashboard "https://raw.githubusercontent.com/VictoriaMetrics/VictoriaLogs/${vlRef}/dashboards/${path}.json";
          in
          {
            victoriametrics = vmDashboard "victoriametrics";
            vmagent = vmDashboard "vmagent";
            vmalert = vmDashboard "vmalert";
            victoriametrics-operator = vmDashboard "operator";
            victorialogs = vlDashboard "vm/victorialogs";
            vlagent = vlDashboard "vm/vlagent";
            victorialogs-explorer = vlDashboard "victorialogs-kubernetes-explorer";
          };
      };
    };
}
