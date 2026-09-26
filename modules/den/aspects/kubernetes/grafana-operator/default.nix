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

        helm.releases.grafana-operator.chart = charts.grafana.grafana-operator;

        # Selected by GrafanaDatasource/GrafanaDashboard CRs' instanceSelector.
        resources.grafanas.grafana.metadata.labels.dashboards = "grafana";

        resources.grafanas.grafana.spec = {
          config = {
            # victoriametrics-metrics-datasource/victoriametrics-logs-datasource
            # (added by victoria-metrics/default.nix) are third-party, unsigned plugins.
            plugins.allow_loading_unsigned_plugins = "victoriametrics-metrics-datasource,victoriametrics-logs-datasource";
            # Needed so the OIDC callback Grafana computes matches Authelia's registered redirect_uri.
            server.root_url = "https://${cluster.methods.mkAppHostname "grafana"}";
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

        # Same names/ports as the vmsingle/vlsingle HTTPRoute backendRefs in
        # victoria-metrics/default.nix — the VM operator names each generated
        # Service after its owning CR.
        resources.grafanaDatasources.victoria-metrics.spec = {
          instanceSelector.matchLabels.dashboards = "grafana";
          datasource = {
            name = "VictoriaMetrics";
            type = "victoriametrics-metrics-datasource";
            access = "proxy";
            url = "http://vmsingle-victoria-metrics-victoria-metrics-k8s-stack.monitoring.svc:8428";
            isDefault = true;
          };
        };

        resources.grafanaDatasources.victoria-logs.spec = {
          instanceSelector.matchLabels.dashboards = "grafana";
          datasource = {
            name = "VictoriaLogs";
            type = "victoriametrics-logs-datasource";
            access = "proxy";
            url = "http://vlsingle-victoria-metrics-victoria-metrics-k8s-stack.monitoring.svc:9428";
          };
        };
      };
    };
}
