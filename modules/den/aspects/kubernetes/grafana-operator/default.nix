_: {
  den.aspects.kubernetes.grafana-operator.k8s-manifests =
    {
      charts,
      generators,
      cluster,
      ...
    }:
    {
      nixidy.applicationImports = [
        (generators.fromChartCRDModule {
          name = "grafana-operator";
          chart = charts.grafana.grafana-operator;
          kindFilter = [
            "Grafana"
            "GrafanaDashboard"
            "GrafanaDatasource"
          ];
        })
      ];

      applications.grafana-operator = {
        namespace = "monitoring";

        resources.ciliumNetworkPolicies = with cluster.methods.netpol; {
          grafana-operator = mkPolicy { "app.kubernetes.io/name" = "grafana-operator"; } {
            egress = [
              apiserverEgress
              (fqdnEgress [ "grafana.com" ] [ 443 ])
            ];
          };
          grafana = mkPolicy { app = "grafana"; } {
            ingress = [ (gatewayIngress 3000) ];
            egress = [
              (fqdnEgress
                [
                  (cluster.methods.mkAppHostname "auth")
                  "grafana.com"
                  # grafana.com redirects plugin downloads here.
                  "storage.googleapis.com"
                ]
                [ 443 ]
              )
            ];
          };
        };

        helm.releases.grafana-operator = {
          chart = charts.grafana.grafana-operator;
          values = {
            serviceMonitor.enabled = true;
            resources = {
              requests = {
                cpu = "10m";
                memory = "96Mi";
              };
              limits.memory = "192Mi";
            };
          };
        };

        # Selected by GrafanaDatasource/GrafanaDashboard CRs' instanceSelector.
        resources.grafanas.grafana.metadata.labels.dashboards = "grafana";

        resources.grafanas.grafana.spec = {
          config = {
            # victoriametrics-metrics-datasource/victoriametrics-logs-datasource
            # (added by victoria-metrics/default.nix) are third-party, unsigned plugins.
            plugins.allow_loading_unsigned_plugins = "victoriametrics-metrics-datasource,victoriametrics-logs-datasource";
            # Needed so the OIDC callback Grafana computes matches Authelia's registered redirect_uri.
            server.root_url = "https://${cluster.methods.mkAppHostname "grafana"}";
            security.disable_gravatar = "true";
          };

          # No dedicated "install a plugin" CR field — Grafana's own image
          # installs plugins named in this env var on startup.
          deployment.spec.template.spec.containers = [
            {
              name = "grafana";
              env = [
                {
                  name = "GF_INSTALL_PLUGINS";
                  value = "victoriametrics-metrics-datasource,victoriametrics-logs-datasource";
                }
              ];
              resources = {
                requests = {
                  cpu = "50m";
                  memory = "384Mi";
                };
                limits.memory = "768Mi";
              };
            }
          ];

          # Lets the operator manage a Gateway API HTTPRoute for this instance
          # directly, wired to its own generated Service.
          httpRoute.spec = {
            parentRefs = [
              {
                group = "gateway.networking.k8s.io";
                kind = "Gateway";
                name = "apps";
                namespace = "envoy-gateway-system";
                sectionName = "https";
              }
            ];
            hostnames = [ (cluster.methods.mkAppHostname "grafana") ];
          };
        };
      };
    };
}
