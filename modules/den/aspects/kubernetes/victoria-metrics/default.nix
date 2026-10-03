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

        resources.ciliumNetworkPolicies =
          with cluster.methods.netpol;
          let
            app = name: { "app.kubernetes.io/name" = name; };
          in
          {
            monitoring-internal.spec = {
              endpointSelector = { };
              ingress = [ { fromEndpoints = [ { } ]; } ];
              egress = [ { toEndpoints = [ { } ]; } ];
            };
            victoria-metrics-operator = mkPolicy (app "victoria-metrics-operator") {
              ingress = [ (webhookIngress 9443) ];
              egress = [ apiserverEgress ];
            };
            kube-state-metrics = mkPolicy (app "kube-state-metrics") {
              egress = [ apiserverEgress ];
            };
            victoria-metrics-sync-job = mkPolicy (app "victoria-metrics-k8s-stack") {
              egress = [
                apiserverEgress
                (fqdnEgress [ "raw.githubusercontent.com" ] [ 443 ])
              ];
            };
            vmagent = mkPolicy (app "vmagent") { egress = [ clusterEgress ]; };
            vlagent = mkPolicy (app "vlagent") { egress = [ apiserverEgress ]; };
            vmsingle = mkPolicy (app "vmsingle") { ingress = [ (gatewayIngress 8428) ]; };
            vlsingle = mkPolicy (app "vlsingle") { ingress = [ (gatewayIngress 9428) ]; };
            vmalert = mkPolicy (app "vmalert") { ingress = [ (gatewayIngress 8080) ]; };
          };

        helm.releases.victoria-metrics = {
          chart = charts.victoriametrics.victoria-metrics-k8s-stack;
          values = {
            grafana.enabled = false;

            fullnameOverride = "victoria-metrics";

            victoria-metrics-operator = {
              admissionWebhooks.certManager.enabled = true;
              resources = {
                requests = {
                  cpu = "10m";
                  memory = "128Mi";
                };
                limits.memory = "256Mi";
              };
            };

            syncJob.resources.requests = {
              cpu = "10m";
              memory = "64Mi";
            };

            kube-state-metrics.resources = {
              requests = {
                cpu = "10m";
                memory = "64Mi";
              };
              limits.memory = "128Mi";
            };

            prometheus-node-exporter.resources = {
              requests = {
                cpu = "10m";
                memory = "32Mi";
              };
              limits.memory = "64Mi";
            };

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
                resources = {
                  requests = {
                    cpu = "100m";
                    memory = "1280Mi";
                  };
                  limits.memory = "2Gi";
                };
              };
              route = mkRoute (cluster.methods.mkAppHostname "metrics");
            };

            vmalert = {
              spec = {
                extraArgs."external.url" = "https://${cluster.methods.mkAppHostname "vmalert"}";
                resources = {
                  requests = {
                    cpu = "10m";
                    memory = "64Mi";
                  };
                  limits.memory = "128Mi";
                };
              };
              route = mkRoute (cluster.methods.mkAppHostname "vmalert");
            };

            vlsingle = {
              enabled = true;
              spec = {
                retentionPeriod = "30d";
                storage.resources.requests.storage = "5Gi";
                resources = {
                  requests = {
                    cpu = "10m";
                    memory = "128Mi";
                  };
                  limits.memory = "512Mi";
                };
              };
              route = mkRoute (cluster.methods.mkAppHostname "logs");
            };

            vlagent = {
              enabled = true;
              spec.resources = {
                requests = {
                  cpu = "10m";
                  memory = "64Mi";
                };
                limits.memory = "128Mi";
              };
            };

            # No CPU limit: the operator's default 200m throttled vmagent
            # in ~30% of CFS periods at 60m average use.
            vmagent.spec.resources = {
              requests = {
                cpu = "100m";
                memory = "128Mi";
              };
              limits.memory = "384Mi";
            };

            internal.vmauth.spec.resources = {
              requests = {
                cpu = "10m";
                memory = "32Mi";
              };
              limits.memory = "64Mi";
            };

            alertmanager.spec.resources = {
              requests = {
                cpu = "10m";
                memory = "64Mi";
              };
              limits.memory = "128Mi";
            };
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
          # --etcd-expose-metrics serves plain HTTP on 2381; 2379 wants a client cert.
          {
            targets = map (address: "${address}:2381") k3sNodeAddresses;
            labels.job = "kube-etcd";
          }
        ];

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
