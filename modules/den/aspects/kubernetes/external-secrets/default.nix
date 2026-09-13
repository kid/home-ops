_: {
  den.aspects.kubernetes.external-secrets.k8s-manifests =
    { charts, generators, ... }:
    {
      nixidy.applicationImports = [
        (generators.fromChartCRDModule {
          name = "external-secrets";
          chart = charts.external-secrets.external-secrets;
          kindFilter = [
            "ClusterSecretStore"
            "PushSecret"
            "ExternalSecret"
          ];
        })
      ];

      applications.external-secrets = {
        namespace = "external-secrets";
        createNamespace = true;
        annotations."argocd.argoproj.io/sync-wave" = "-3";

        helm.releases.external-secrets.chart = charts.external-secrets.external-secrets;

        resources.clusterSecretStores.onepassword.spec.provider.onepasswordSDK = {
          vault = "home-ops";
          auth.serviceAccountSecretRef = {
            name = "onepassword-service-account-token";
            namespace = "external-secrets";
            key = "token";
          };
        };

        resources.clusterSecretStores.openbao.spec.provider.vault = {
          server = "http://openbao.openbao.svc:8200";
          path = "secret";
          version = "v2";
          auth.kubernetes = {
            mountPath = "kubernetes";
            role = "eso-cluster";
            serviceAccountRef = {
              name = "external-secrets";
              namespace = "external-secrets";
            };
          };
        };
      };
    };
}
