_: {
  den.aspects.kubernetes.grafana-operator.k8s-manifests =
    {
      charts,
      generators,
      cluster,
      ...
    }:
    let
      # The operator runs Grafana as this user.
      uid = 10001;
    in
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
        # The kopiur webhook admits the backup objects.
        flux.dependsOn = [ "kopiur-config" ];

        # Grafana's SQLite database: users, sessions, preferences. Plugins are
        # downloaded again on startup.
        imports = [
          {
            resources = cluster.methods.mkKopiurBackup {
              name = "grafana";
              inherit uid;
              ignore = [ "/plugins" ];
            };
          }
        ];

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
              # Kanidm token and userinfo calls.
              gatewayEgress
              (fqdnEgress
                [
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
            # One replica, no leader election (lease renewals were most of
            # etcd's writes); Recreate below keeps an update from running two.
            leaderElect = false;
            logging.encoder = "json";
            resources = {
              requests = {
                cpu = "10m";
                memory = "96Mi";
              };
              limits.memory = "192Mi";
            };
          };
        };

        resources.deployments.grafana-operator.spec.strategy.type = "Recreate";

        # Selected by GrafanaDatasource/GrafanaDashboard CRs' instanceSelector.
        resources.grafanas.grafana.metadata.labels.dashboards = "grafana";

        resources.grafanas.grafana.spec = {
          config = {
            # victoriametrics-metrics-datasource/victoriametrics-logs-datasource
            # (added by victoria-metrics/default.nix) are third-party, unsigned plugins.
            plugins = {
              allow_loading_unsigned_plugins = "victoriametrics-metrics-datasource,victoriametrics-logs-datasource";
              # Updating a bundled plugin (prometheus, loki, ...) to a newer catalog
              # version unloads it, then fails on the read-only root filesystem,
              # leaving it unregistered (https://github.com/grafana/grafana/issues/132528).
              preinstall_auto_update = "false";
            };
            # Needed so the OIDC callback Grafana computes matches Kanidm's registered redirect URL.
            server.root_url = "https://${cluster.methods.mkAppHostname "grafana"}";
            security.disable_gravatar = "true";
            "log.console".format = "json";
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

          # The operator merges these over its own: grafana-data replaces its emptyDir.
          deployment.spec = {
            # The claim is ReadWriteOncePod.
            strategy.type = "Recreate";
            template.spec = {
              # Makes the volume writable by the operator's non-root user.
              securityContext = {
                fsGroup = uid;
                fsGroupChangePolicy = "OnRootMismatch";
              };
              volumes = [
                {
                  name = "grafana-data";
                  persistentVolumeClaim.claimName = "grafana";
                }
              ];
            };
          };

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
