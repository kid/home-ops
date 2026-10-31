# Publishes the cluster CA (modules/den/aspects/kubernetes/cert-manager/default.nix)
# as the cluster-ca ConfigMap in every namespace, so BackendTLSPolicy (which
# can't read Secrets) and workloads can trust in-cluster certificates.
_: {
  den.aspects.kubernetes.trust-manager.k8s-manifests =
    {
      charts,
      generators,
      cluster,
      ...
    }:
    {
      nixidy.applicationImports = [
        (generators.fromChartCRDModule {
          name = "trust-manager";
          chart = charts.jetstack.trust-manager;
          kindFilter = [ "Bundle" ];
          extraOpts = [
            "--set"
            "crds.enabled=true"
          ];
        })
      ];

      applications.trust-manager = {
        namespace = "cert-manager";
        flux.dependsOn = [ "cert-manager" ];

        resources.ciliumNetworkPolicies = with cluster.methods.netpol; {
          trust-manager = mkPolicy { "app.kubernetes.io/name" = "trust-manager"; } {
            ingress = [
              (webhookIngress 6443)
              (scrapeIngress [ 9402 ])
            ];
            egress = [ apiserverEgress ];
          };
        };

        helm.releases.trust-manager = {
          chart = charts.jetstack.trust-manager;
          values = {
            crds.enabled = true;
            app.metrics.service.servicemonitor.enabled = true;
            defaultPackage.resources.requests = {
              cpu = "10m";
              memory = "32Mi";
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

      # Separate from the controller: its webhook must serve before the Bundle is applied.
      applications.trust-manager-config = {
        namespace = "cert-manager";
        flux.dependsOn = [ "trust-manager" ];

        resources.bundles.cluster-ca.spec = {
          sources = [
            {
              secret = {
                name = "cluster-ca";
                key = "ca.crt";
              };
            }
          ];
          target.configMap.key = "ca.crt";
        };
      };
    };
}
