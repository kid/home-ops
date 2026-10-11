# MiroirNode isn't a core Kubernetes type, so nixidy has no built-in typed
# options for it — generators.fromChartCRDModule generates it live from
# the chart's own CRDs, installed by Helm automatically.
_: {
  # miroir-agent runs hostNetwork: true with its own port 9810.
  den.aspects.kubernetes.miroir.firewall-ports = _: [
    {
      port = 9810;
      protocol = "TCP";
      description = "miroir-agent";
      from = [
        "cluster"
        "remote-node"
      ];
    }
    # DRBD replication links: one port per replicated volume, ascending
    # from the chart's drbd.portBase (7000) with no upper bound of its own.
    {
      port = 7000;
      endPort = 7999;
      protocol = "TCP";
      description = "miroir DRBD replication";
      from = [
        "cluster"
        "remote-node"
      ];
    }
  ];

  den.aspects.kubernetes.miroir.k8s-manifests =
    {
      charts,
      generators,
      cluster,
      lib,
      miroir-nodes ? [ ],
      ...
    }:
    {
      nixidy.applicationImports = [
        (generators.fromChartCRDModule {
          name = "miroir";
          chart = charts.home-operations.miroir;
          kindFilter = [ "MiroirNode" ];
        })
        (generators.fromChartCRDModule {
          name = "snapshot-controller";
          chart = charts.home-operations.snapshot-controller;
          kindFilter = [ "VolumeSnapshotClass" ];
        })
      ];

      applications.miroir = {
        namespace = "miroir-system";

        resources.ciliumNetworkPolicies = with cluster.methods.netpol; {
          miroir-controller =
            mkPolicy
              {
                "app.kubernetes.io/name" = "miroir";
                "app.kubernetes.io/component" = "controller";
              }
              {
                ingress = [ (scrapeIngress [ 8081 ]) ];
                egress = [ apiserverEgress ];
              };
        };

        helm.releases.miroir = {
          chart = charts.home-operations.miroir;
          values = {
            monitoring = {
              podMonitor.enabled = true;
              dashboards = {
                enabled = true;
                grafanaOperator = {
                  enabled = true;
                  matchLabels.dashboards = "grafana";
                };
              };
            };
            resources.requests.memory = "64Mi";
            sidecars.resizer.resources.requests.memory = "64Mi";
            agent = {
              resources = {
                requests.memory = "64Mi";
                limits.memory = "192Mi";
              };
              registrar.resources.requests.memory = "32Mi";
            };
          };
        };

        resources.miroirNodes = lib.listToAttrs (
          map (
            n:
            lib.nameValuePair n.hostname {
              spec.pools = [
                {
                  name = "default";
                  lvmthin.device = n.device;
                }
              ];
            }
          ) miroir-nodes
        );

        resources.volumeSnapshotClasses.miroir = {
          metadata.annotations."snapshot.storage.kubernetes.io/is-default-class" = "true";
          driver = "miroir.home-operations.com";
          deletionPolicy = "Delete";
        };

        resources.storageClasses.miroir = {
          metadata.annotations."storageclass.kubernetes.io/is-default-class" = "true";
          provisioner = "miroir.home-operations.com";
          volumeBindingMode = "WaitForFirstConsumer";
          allowVolumeExpansion = true;
          parameters = {
            "miroir.home-operations.com/replicas" = "1";
            "csi.storage.k8s.io/fstype" = "ext4";
          };
        };

        # A second class, not a change to the default one: StorageClass
        # parameters are immutable, and a volume cannot gain a replication
        # layer in place.
        resources.storageClasses.miroir-replicated = {
          provisioner = "miroir.home-operations.com";
          volumeBindingMode = "WaitForFirstConsumer";
          allowVolumeExpansion = true;
          parameters = {
            "miroir.home-operations.com/replicas" = "2";
            "csi.storage.k8s.io/fstype" = "ext4";
          };
        };
      };
    };
}
