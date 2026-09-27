_: {
  den.aspects.kubernetes.victoria-metrics.k8s-manifests =
    {
      charts,
      generators,
      cluster,
      lib,
      k3s-nodes ? [ ],
      ...
    }:
    let
      k3sNodeAddresses = map (n: n.address) (lib.filter (n: n.address != null) k3s-nodes);

      mkTrustedNetworkOnly = httpRouteName: {
        targetRefs = [
          {
            group = "gateway.networking.k8s.io";
            kind = "HTTPRoute";
            name = httpRouteName;
          }
        ];
        authorization = {
          defaultAction = "Deny";
          rules = [
            {
              action = "Allow";
              principal.clientCIDRs = [ "10.0.100.0/24" ];
            }
          ];
        };
      };

      mkStaticScrapeEndpoint =
        {
          job,
          port,
        }:
        {
          targets = map (address: "${address}:${toString port}") k3sNodeAddresses;
          labels.job = job;
          bearerTokenFile = "/var/run/secrets/kubernetes.io/serviceaccount/token";
          scheme = "https";
          tlsConfig.insecureSkipVerify = true;
        };

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
      nixidy.applicationImports = [
        (generators.fromChartCRDModule {
          name = "victoria-metrics";
          chart = charts.victoriametrics.victoria-metrics-k8s-stack;
          kindFilter = [ "VMStaticScrape" ];
        })
      ];

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

            # CoreDNS is now scraped via its own chart's ServiceMonitor
            # (modules/den/aspects/kubernetes/coredns/default.nix).
            coreDns.enabled = false;

            # vmScrape=null drops the chart's own broken scrape config (see
            # the VMStaticScrape below) while keeping the mixin alert rules.
            kubeScheduler = {
              enabled = true;
              vmScrape = null;
            };
            kubeControllerManager = {
              enabled = true;
              vmScrape = null;
            };
            kubeEtcd = {
              enabled = true;
              vmScrape = null;
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

        resources.vmStaticScrapes.k3s-control-plane.spec.targetEndpoints = [
          (mkStaticScrapeEndpoint {
            job = "kube-scheduler";
            port = 10259;
          })
          (mkStaticScrapeEndpoint {
            job = "kube-controller-manager";
            port = 10257;
          })
          (mkStaticScrapeEndpoint {
            job = "kube-etcd";
            port = 2379;
          })
        ];

        resources.securityPolicies = {
          vmsingle.spec = mkTrustedNetworkOnly "vmsingle-victoria-metrics";
          vlsingle.spec = mkTrustedNetworkOnly "vlsingle-victoria-metrics";
        }
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
