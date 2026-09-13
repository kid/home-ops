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

        # Resource name must match the real Kubernetes node name.
        resources.miroirNodes.k3s-prd-0.spec.pools = [
          {
            name = "default";
            # CONFIRM this by-id path once `terraform apply` attaches the disk.
            lvmthin.device = "/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_incus_miroir-data";
          }
        ];

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
