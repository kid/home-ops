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
            "ExternalSecret"
            "Password"
          ];
        })
      ];

      applications.external-secrets = {
        namespace = "external-secrets";

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
          values = {
            serviceMonitor = {
              enabled = true;
              # Default renderMode (skipIfMissing) checks the live API server
              # for the CRD — nixidy renders offline, so that check is always
              # false and the ServiceMonitor silently never renders.
              renderMode = "alwaysRender";
            };
            resources = {
              requests = {
                cpu = "20m";
                memory = "192Mi";
              };
              limits.memory = "768Mi";
            };
            # Without it the Go GC ignores the cgroup limit: startup briefly
            # holds ~430MB of mostly freed heap (live ~90MB) and gets OOMKilled.
            extraEnv = [
              {
                name = "GOMEMLIMIT";
                valueFrom.resourceFieldRef.resource = "limits.memory";
              }
            ];
            webhook.resources = {
              requests = {
                cpu = "10m";
                memory = "64Mi";
              };
              limits.memory = "192Mi";
            };
            certController.resources = {
              requests = {
                cpu = "10m";
                memory = "128Mi";
              };
              limits.memory = "256Mi";
            };
          };
        };
      };

      # Separate from the controller: its webhook must serve before the store is applied.
      applications.external-secrets-config = {
        namespace = "external-secrets";
        flux.dependsOn = [ "external-secrets" ];

        resources.clusterSecretStores.onepassword.spec.provider.onepasswordSDK = {
          vault = cluster.secrets.onepasswordVault;
          auth.serviceAccountSecretRef = {
            name = "onepassword-service-account-token";
            namespace = "external-secrets";
            key = "token";
          };
          # The account is capped at 1,000 requests per 24h, shared by every
          # service account, and each ExternalSecret re-reads every ref on its
          # default 1h refresh. Serve those refreshes from memory: a secret
          # rotated in 1Password reaches the cluster within a day, or at once
          # after an ESO restart.
          cache.ttl = "24h";
        };
      };
    };
}
