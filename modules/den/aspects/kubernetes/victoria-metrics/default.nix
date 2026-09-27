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

            fullnameOverride = "victoria-metrics";

            victoria-metrics-operator.admissionWebhooks.certManager.enabled = true;

            defaultDashboards = {
              grafanaOperator.enabled = true;
              dashboards = {
                grafana-overview.enabled = true;
                victorialogs-cluster.enabled = true;
                victorialogs-single-node.enabled = true;
                victorialogs-vlagent.enabled = true;
              };
            };

            external.grafana = {
              host = "https://${cluster.methods.mkAppHostname "grafana"}";
              datasource = "VictoriaMetrics";
            };

            vmsingle = {
              spec = {
                retentionPeriod = "30d";
                storage.resources.requests.storage = "5Gi";
              };
              route = mkRoute (cluster.methods.mkAppHostname "metrics");
            };

            vmalert = {
              spec.extraArgs."external.url" = "https://${cluster.methods.mkAppHostname "vmalert"}";
              route = mkRoute (cluster.methods.mkAppHostname "vmalert");
            };

            vlsingle = {
              enabled = true;
              spec = {
                retentionPeriod = "30d";
                storage.resources.requests.storage = "5Gi";
              };
              route = mkRoute (cluster.methods.mkAppHostname "logs");
            };

            vlagent.enabled = true;
          };
        };

        resources.securityPolicies =
          (cluster.methods.mkForwardAuth {
            name = "vmsingle";
            httpRouteName = "vmsingle-victoria-metrics";
          }).securityPolicies
          // (cluster.methods.mkForwardAuth {
            name = "vlsingle";
            httpRouteName = "vlsingle-victoria-metrics";
          }).securityPolicies
          // (cluster.methods.mkForwardAuth {
            name = "vmalert";
            httpRouteName = "vmalert-victoria-metrics";
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

        resources.grafanaDatasources.victoria-metrics-prometheus.spec = {
          instanceSelector.matchLabels.dashboards = "grafana";
          datasource = {
            name = "Prometheus";
            uid = "VictoriaMetrics";
            type = "prometheus";
            access = "proxy";
            url = "http://vmsingle-victoria-metrics.monitoring.svc:8428/prometheus";
            isDefault = false;
            jsonData.timeInterval = "30s";
          };
        };
      };
    };
}
