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
  ];

  den.aspects.kubernetes.miroir.k8s-manifests =
    {
      charts,
      generators,
      lib,
      cluster,
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
          chart = charts.piraeusdatastore.snapshot-controller;
          kindFilter = [ "VolumeSnapshotClass" ];
        })
      ];

      applications.miroir = {
        namespace = "miroir-system";
        createNamespace = true;

        helm.releases.miroir.chart = charts.home-operations.miroir;

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
          ) cluster.methods.miroirNodes
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
            # "2" would leave PVCs Pending — no second node to place a replica on yet.
            "miroir.home-operations.com/replicas" = "1";
            "csi.storage.k8s.io/fstype" = "ext4";
          };
        };
      };
    };
}
