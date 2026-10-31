_: {
  # Host ports vmagent scrapes: node-exporter on every node, and the
  # control-plane components of the static scrapes below.
  den.aspects.kubernetes.victoria-metrics.firewall-ports = _: [
    {
      port = 9100;
      protocol = "TCP";
      description = "node-exporter";
      from = [ "cluster" ];
    }
    {
      port = 10259;
      protocol = "TCP";
      description = "kube-scheduler metrics";
      from = [ "cluster" ];
      controlPlane = true;
    }
    {
      port = 10257;
      protocol = "TCP";
      description = "kube-controller-manager metrics";
      from = [ "cluster" ];
      controlPlane = true;
    }
    {
      port = 2381;
      protocol = "TCP";
      description = "etcd metrics";
      from = [ "cluster" ];
      controlPlane = true;
    }
  ];

  den.aspects.kubernetes.victoria-metrics.k8s-manifests =
    {
      charts,
      generators,
      cluster,
      config,
      lib,
      k3s-nodes ? [ ],
      ...
    }:
    let
      # Control-plane ports only exist on servers.
      k3sNodeAddresses = map (n: n.address) (
        lib.filter (n: n.address != null && n.role == "server") k3s-nodes
      );

      # k3s runs every control-plane component in one process, and each of
      # their ports serves that process's whole metric registry (~80k series,
      # mostly apiserver_*). Only the apiserver job keeps all of it; the others
      # keep their own families plus the process-level ones their dashboards use.
      processMetrics = "rest_client|process|go";

      # That registry outgrows vmagent's default 16 MiB limit: its apiserver
      # histograms gain series until k3s restarts. The limit applies to the
      # raw body, before any metricRelabelConfigs.
      maxScrapeSize = "64MiB";

      mkStaticScrapeEndpoint =
        {
          job,
          port,
          keep,
        }:
        {
          targets = map (address: "${address}:${toString port}") k3sNodeAddresses;
          labels.job = job;
          bearerTokenFile = "/var/run/secrets/kubernetes.io/serviceaccount/token";
          scheme = "https";
          tlsConfig.insecureSkipVerify = true;
          max_scrape_size = maxScrapeSize;
          metricRelabelConfigs = [
            {
              action = "keep";
              sourceLabels = [ "__name__" ];
              regex = "(${keep}|${processMetrics})_.*";
            }
          ];
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
        # The operator webhook's certificate.
        flux.dependsOn = [ "cert-manager" ];

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
            # Queried by the MCP servers (mcp.nix).
            vmsingle = mkPolicy (app "vmsingle") {
              ingress = [
                (gatewayIngress 8428)
                (fromPods (app "mcp-victoriametrics") [ 8428 ])
              ];
            };
            vlsingle = mkPolicy (app "vlsingle") {
              ingress = [
                (gatewayIngress 9428)
                (fromPods (app "mcp-victorialogs") [ 9428 ])
              ];
            };
            vmalert = mkPolicy (app "vmalert") { ingress = [ (gatewayIngress 8080) ]; };
            # Their config-reloader sidecars watch the config Secret.
            vmalertmanager = mkPolicy (app "vmalertmanager") { egress = [ apiserverEgress ]; };
            vmauth = mkPolicy (app "vmauth") { egress = [ apiserverEgress ]; };
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
              # A pre-delete Helm hook deleting every VM resource in the namespace.
              crds.cleanup.enabled = false;
            };

            syncJob.resources.requests = {
              cpu = "10m";
              memory = "64Mi";
            };

            kubelet.vmScrapes.kubelet.spec.max_scrape_size = maxScrapeSize;

            # The kubelet port of a k3s server serves the same whole-process
            # registry as the apiserver job; drop the other components'
            # families there. A list replaces the chart's, so its three
            # default entries are restated.
            kubelet.vmScrapes.kubelet.spec.metricRelabelConfigs = [
              {
                action = "labeldrop";
                regex = "(uid)";
              }
              {
                action = "labeldrop";
                regex = "(id|name)";
              }
              {
                action = "drop";
                source_labels = [ "__name__" ];
                regex = "(rest_client_request_duration_seconds_bucket|rest_client_request_duration_seconds_sum|rest_client_request_duration_seconds_count)";
              }
              {
                action = "drop";
                source_labels = [ "__name__" ];
                regex = "(apiserver|etcd|scheduler|apiextensions|workqueue)_.*";
              }
            ];

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

            # Rules that are empty by design here: no container sets a CPU limit,
            # count:up0 is empty while every target is up, and the scheduler
            # quantiles are NaN (dropped) unless a pod was scheduled in the last 5m.
            defaultRules = {
              groups = {
                "k8s.rules.container_cpu_limits".enabled = false;
                "kube-prometheus-general.rules".rules."count:up0".enabled = false;
              };
              rules.RecordingRulesNoData.spec.expr = ''sum(vmalert_recording_rules_last_evaluation_samples{group!="kube-scheduler.rules"}) without(id) < 1'';
            };

            vmsingle = {
              spec = {
                retentionPeriod = "30d";
                # 15 days of data filled 5Gi and put the storage in read-only mode.
                storage.resources.requests.storage = "10Gi";
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

          # The chart's apiserver endpoints, plus max_scrape_size. Composes
          # with the default transformer, which a release's own replaces.
          transformer =
            manifests:
            map (
              m:
              if m.kind == "VMServiceScrape" && m.metadata.name == "victoria-metrics-kube-api-server" then
                lib.updateManyAttrsByPath [
                  {
                    path = [
                      "spec"
                      "endpoints"
                    ];
                    update = map (e: e // { max_scrape_size = maxScrapeSize; });
                  }
                ] m
              else
                m
            ) (config.nixidy.defaults.helm.transformer manifests);
        };

        resources.vmStaticScrapes.k3s-control-plane.spec.targetEndpoints = [
          (mkStaticScrapeEndpoint {
            job = "kube-scheduler";
            port = 10259;
            keep = "scheduler";
          })
          (mkStaticScrapeEndpoint {
            job = "kube-controller-manager";
            port = 10257;
            keep = "workqueue|node_collector|garbagecollector|pv_collector|[a-z_]+_controller|root_ca_cert_publisher";
          })
          # --etcd-expose-metrics serves plain HTTP on 2381; 2379 wants a client cert.
          {
            targets = map (address: "${address}:2381") k3sNodeAddresses;
            labels.job = "kube-etcd";
          }
        ];

        # The sync job, a post-install/upgrade Helm hook rendered as a plain
        # Job, creates the chart's dashboards and rules from this ConfigMap.
        # Hashing it into the template makes Flux recreate the Job, and so
        # rerun it, when the ConfigMap changes.
        resources.jobs.victoria-metrics-sync-job.spec.template.metadata.annotations."checksum/config" =
          let
            configMap =
              lib.findFirst (o: o.kind == "ConfigMap" && o.metadata.name == "victoria-metrics-sync-job-config")
                (throw "victoria-metrics-sync-job-config not rendered")
                config.applications.victoria-metrics.helm.releases.victoria-metrics.objects;
          in
          builtins.hashString "sha256" (builtins.toJSON configMap.data);

        # The chart names each route <component>-victoria-metrics.
        imports =
          lib.mapAttrsToList
            (
              name: host:
              cluster.methods.mkOidcAuth {
                inherit name;
                httpRouteName = "${name}-victoria-metrics";
                hostname = cluster.methods.mkAppHostname host;
                group = "admins";
              }
            )
            {
              vmsingle = "metrics";
              vlsingle = "logs";
              vmalert = "vmalert";
            };

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
