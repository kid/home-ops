# Syncs hubble-ca-secret into a ConfigMap so BackendTLSPolicy can read it
# (it can't read Secrets).
_: {
  den.aspects.kubernetes.trust-manager.k8s-manifests =
    { charts, generators, ... }:
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

        helm.releases.trust-manager = {
          chart = charts.jetstack.trust-manager;
          values.crds.enabled = true;
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
