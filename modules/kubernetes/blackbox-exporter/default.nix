# Probes the NFS server; prometheus-adapter serves the result to the HPAs
# built by cluster.methods.mkNfsScaler.
{ config, lib, ... }:
let
  # The nodes reach truenas on the Storage VLAN, not through the router.
  nfsAddr =
    (lib.findFirst (
      i: i.network == "Storage"
    ) (throw "truenas has no Storage interface") config.den.devices.truenas.interfaces).address;
in
{
  den.aspects.kubernetes.blackbox-exporter.k8s-manifests =
    { charts, cluster, ... }:
    {
      applications.blackbox-exporter = {
        namespace = "monitoring";
        # The VMProbe CRD and the operator webhook that admits it.
        flux.dependsOn = [ "victoria-metrics" ];

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
