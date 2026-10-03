# Syncs hubble-ca-secret into a ConfigMap so BackendTLSPolicy can read it
# (it can't read Secrets).
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

        resources.bundles.internal-ca.spec = {
          sources = [
            {
              secret = {
                name = "hubble-ca-secret";
                key = "ca.crt";
              };
            }
          ];
          target = {
            configMap.key = "ca.crt";
            namespaceSelector.matchLabels."kubernetes.io/metadata.name" = "argocd";
          };
        };
      };
    };
}
