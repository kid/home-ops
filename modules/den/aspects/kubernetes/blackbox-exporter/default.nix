# Probes the NFS server; prometheus-adapter serves the result to the HPAs
# built by cluster.methods.mkNfsScaler.
{ config, ... }:
let
  nfsAddr = config.den.devices.truenas.address;
in
{
  # Pods are masqueraded to the node address, so this also covers the
  # kubelet's own NFS mounts.
  den.aspects.kubernetes.blackbox-exporter.firewall = { cluster, ... }: [
    {
      inherit (cluster) network;
      forward = [
        {
          action = "accept";
          dst_address = nfsAddr;
          dst_port = 2049;
          protocol = "tcp";
          comment = "Allow access to truenas NFS from K3s";
        }
      ];
    }
  ];

  den.aspects.kubernetes.blackbox-exporter.k8s-manifests =
    { charts, cluster, ... }:
    {
      applications.blackbox-exporter = {
        namespace = "monitoring";

        resources.ciliumNetworkPolicies = with cluster.methods.netpol; {
          blackbox-exporter = mkPolicy { "app.kubernetes.io/name" = "prometheus-blackbox-exporter"; } {
            egress = [
              {
                toCIDR = [ "${nfsAddr}/32" ];
                toPorts = tcp [ 2049 ];
              }
            ];
          };
        };

        helm.releases.blackbox-exporter = {
          chart = charts.prometheus-community.prometheus-blackbox-exporter;
          values = {
            fullnameOverride = "blackbox-exporter";
            config.modules.tcp_connect = {
              prober = "tcp";
              timeout = "5s";
            };
            resources = {
              requests = {
                cpu = "10m";
                memory = "32Mi";
              };
              limits.memory = "64Mi";
            };
          };
        };

        resources.vmProbes.nfs.spec = {
          jobName = "nfs";
          interval = "15s";
          module = "tcp_connect";
          vmProberSpec.url = "blackbox-exporter.monitoring.svc:9115";
          targets.staticConfig.targets = [ "${nfsAddr}:2049" ];
        };
      };
    };
}
