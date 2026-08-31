# miroir, replacing OpenEBS ZFS-LocalPV as the cluster's storage
# provisioner, using node1's zroot/miroir dataset as its ZFS pool
# (reserved via modules/den/aspects/services/k3s/miroir.nix's `datasets`
# quirk, den.aspects.k3s-miroir, included on node1).
#
# MiroirNode isn't a core Kubernetes type, so nixidy has no built-in typed
# options for it — generators.fromChartCRDModule generates it live from
# the chart's own CRDs (miroir ships them under crds/, installed by Helm
# automatically, no crds.enabled-style value needed).
#
# node1 is the only cluster node today, so the default StorageClass stays
# replicas: "1" (local only) — a replicas: "2" class would leave PVCs
# Pending with nowhere to place a second replica. DRBD9 is loaded on the
# host already (see miroir.nix) so a replicated class is a small
# follow-up once a 2nd node exists, not a redo.
_: {
  # miroir-agent runs hostNetwork: true with its own port 9810 — required
  # once cilium.hostFirewall.enabled flips on.
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
    { charts, generators, ... }:
    {
      nixidy.applicationImports = [
        (generators.fromChartCRDModule {
          name = "miroir";
          chart = charts.home-operations.miroir;
          kindFilter = [ "MiroirNode" ];
        })
      ];

      applications.miroir = {
        namespace = "miroir-system";
        createNamespace = true;

        helm.releases.miroir.chart = charts.home-operations.miroir;

        resources.miroirNodes.node1.spec.pools = [
          {
            name = "default";
            zfs.dataset = "zroot/miroir";
          }
        ];

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
      };
    };
}
