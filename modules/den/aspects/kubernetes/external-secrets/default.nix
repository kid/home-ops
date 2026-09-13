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

        helm.releases.external-secrets.chart = charts.external-secrets.external-secrets;

        resources.clusterSecretStores.onepassword.spec.provider.onepasswordSDK = {
          vault = "home-ops/prd";
          auth.serviceAccountSecretRef = {
            name = "onepassword-service-account-token";
            namespace = "external-secrets";
            key = "token";
          };
        };
      };
    };
}
