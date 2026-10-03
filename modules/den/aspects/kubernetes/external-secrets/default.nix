_: {
  den.aspects.kubernetes.external-secrets.k8s-manifests =
    {
      charts,
      generators,
      cluster,
      ...
    }:
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
        annotations."argocd.argoproj.io/sync-wave" = "-3";

        resources.ciliumNetworkPolicies =
          with cluster.methods.netpol;
          let
            app = name: { "app.kubernetes.io/name" = name; };
          in
          {
            external-secrets = mkPolicy (app "external-secrets") {
              ingress = [ (scrapeIngress [ 8080 ]) ];
              egress = [
                apiserverEgress
                # 1Password's SDK endpoints are not a stable, documented host list.
                (worldEgress [ 443 ])
              ];
            };
            external-secrets-webhook = mkPolicy (app "external-secrets-webhook") {
              ingress = [
                (webhookIngress 10250)
                (scrapeIngress [ 8080 ])
              ];
              egress = [ apiserverEgress ];
            };
            external-secrets-cert-controller = mkPolicy (app "external-secrets-cert-controller") {
              ingress = [ (scrapeIngress [ 8080 ]) ];
              egress = [ apiserverEgress ];
            };
          };

        helm.releases.external-secrets = {
          chart = charts.external-secrets.external-secrets;
          values.serviceMonitor = {
            enabled = true;
            # Default renderMode (skipIfMissing) checks the live API server
            # for the CRD — nixidy renders offline, so that check is always
            # false and the ServiceMonitor silently never renders.
            renderMode = "alwaysRender";
          };
        };

        resources.clusterSecretStores.onepassword.spec.provider.onepasswordSDK = {
          vault = cluster.secrets.onepasswordVault;
          auth.serviceAccountSecretRef = {
            name = "onepassword-service-account-token";
            namespace = "external-secrets";
            key = "token";
          };
        };
      };
    };
}
