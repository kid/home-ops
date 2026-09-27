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

            # Renders every default dashboard (VictoriaMetrics/VictoriaLogs's
            # own plus community ones — node-exporter-full, kubernetes-views,
            # etcd, kube-prometheus) as GrafanaDashboard CRs via a PostSync
            # Job (helm.sh/hook maps to ArgoCD's own PostSync hook).
            defaultDashboards.grafanaOperator.enabled = true;

            # grafana.enabled = false means vm-k8s-stack.grafana.addr falls
            # back to external.grafana.host — used to build the "view in
            # Grafana Explore" link in vmalert's own alert notifications.
            external.grafana = {
              host = "https://${cluster.methods.mkAppHostname "grafana"}";
              datasource = "VictoriaMetrics";
            };

            vmsingle = {
              spec = {
                retentionPeriod = "30d";
                # 20Gi default won't fit alongside vlsingle on the 20GiB miroir-data disk.
                storage.resources.requests.storage = "5Gi";
              };
              route = mkRoute (cluster.methods.mkAppHostname "metrics");
            };

            vmalert = {
              spec.extraArgs."external.url" = "https://${cluster.methods.mkAppHostname "vmalert"}";
              route = mkRoute (cluster.methods.mkAppHostname "vmalert");
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

        # VMUI, VictoriaLogs' own UI, and vmalert's UI have no login of their
        # own — HTTPRoute names below match the chart's own naming (see the
        # rendered HTTPRoute-*.yaml under manifests/prd/victoria-metrics/).
        # `//` merges the three calls' distinct securityPolicies keys, not
        # the outer attrset.
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

        # The chart's own default dashboards (including community ones like
        # node-exporter-full/kubernetes-views/etcd) filter their datasource
        # variable by type: "prometheus" — VictoriaMetrics implements the
        # Prometheus HTTP API, so a plain prometheus-type datasource resolves
        # them directly. Kept separate from the native-plugin one above,
        # which keeps its own query builder UI. uid must be "VictoriaMetrics"
        # exactly — the sync-job's generated dashboard panels hardcode that
        # uid (from defaultDatasources.victoriametrics.datasources' own
        # unrelated chart default, which we never override but which still
        # feeds this), not a datasource-variable lookup by type.
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

        # Not part of the chart's own default dashboard set (that's
        # metrics-focused), so kept as its own resource alongside the
        # sync-job-generated ones above.
        resources.grafanaDashboards.victorialogs-explorer.spec =
          let
            # renovate: datasource=github-releases depName=VictoriaMetrics/VictoriaLogs
            vlRef = "v1.52.0";
          in
          {
            instanceSelector.matchLabels.dashboards = "grafana";
            url = "https://raw.githubusercontent.com/VictoriaMetrics/VictoriaLogs/${vlRef}/dashboards/victorialogs-kubernetes-explorer.json";
          };
      };
    };
}
