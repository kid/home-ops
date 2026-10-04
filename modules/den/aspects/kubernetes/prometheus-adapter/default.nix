# External Metrics API for HPAs; kube 1.37's HPA scale-to-zero needs an
# external metric to scale back up from.
_:
let
  # Runs an app only while the NFS server answers. The scaled workload must
  # not render spec.replicas, or ArgoCD's selfHeal fights the HPA.
  mkNfsScaler =
    {
      name,
      kind ? "Deployment",
      replicas ? 1,
    }:
    {
      horizontalPodAutoscalers.${name}.spec = {
        scaleTargetRef = {
          apiVersion = "apps/v1";
          inherit kind name;
        };
        minReplicas = 0;
        maxReplicas = replicas;
        # The default 5m window would keep pods on a dead mount.
        behavior.scaleDown.stabilizationWindowSeconds = 0;
        metrics = [
          {
            type = "External";
            external = {
              metric.name = "nfs_server_up";
              # AverageValue, not Value: Value scales relative to the
              # current count, so it never gets past 1 after a scale to 0.
              target = {
                type = "AverageValue";
                averageValue = "${toString (1000 / replicas)}m";
              };
            };
          }
        ];
      };
    };
in
{
  den.clusters.prd.methods.mkNfsScaler = mkNfsScaler;

  den.aspects.kubernetes.prometheus-adapter.k8s-manifests =
    { charts, cluster, ... }:
    {
      applications.prometheus-adapter = {
        namespace = "monitoring";

        resources.ciliumNetworkPolicies = with cluster.methods.netpol; {
          prometheus-adapter = mkPolicy { "app.kubernetes.io/name" = "prometheus-adapter"; } {
            ingress = [ (webhookIngress 6443) ];
            egress = [ apiserverEgress ];
          };
        };

        helm.releases.prometheus-adapter = {
          chart = charts.prometheus-community.prometheus-adapter;
          # Without it the offline render falls back to the removed
          # v1beta1 APIService.
          extraOpts = [
            "--api-versions"
            "apiregistration.k8s.io/v1"
          ];
          values = {
            prometheus = {
              url = "http://vmsingle-victoria-metrics.monitoring.svc";
              port = 8428;
            };
            rules = {
              default = false;
              external = [
                {
                  seriesQuery = ''probe_success{job="nfs"}'';
                  resources.namespaced = false;
                  name.as = "nfs_server_up";
                  metricsQuery = "min(<<.Series>>{<<.LabelMatchers>>})";
                }
              ];
            };
            resources = {
              requests = {
                cpu = "10m";
                memory = "64Mi";
              };
              limits.memory = "128Mi";
            };
          };
        };
      };
    };
}
