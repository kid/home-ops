_: {
  den.aspects.kubernetes.external-dns-cloudflare.k8s-manifests =
    { charts, cluster, ... }:
    {
      applications.external-dns-cloudflare = {
        namespace = "external-dns";

        resources.ciliumNetworkPolicies = with cluster.methods.netpol; {
          external-dns-cloudflare = mkPolicy { "app.kubernetes.io/instance" = "external-dns-cloudflare"; } {
            ingress = [ (scrapeIngress [ 7979 ]) ];
            egress = [
              apiserverEgress
              (fqdnEgress [ "api.cloudflare.com" ] [ 443 ])
            ];
          };
        };

        helm.releases.external-dns-cloudflare = {
          chart = charts.kubernetes-sigs.external-dns;
          values = {
            fullnameOverride = "external-dns-cloudflare";
            replicaCount = 1;
            sources = [ "gateway-httproute" ];
            serviceMonitor.enabled = true;

            registry = "txt";
            txtOwnerId = cluster.name;
            domainFilters = [ cluster.domain ];
            policy = "upsert-only";

            provider.name = "cloudflare";

            env = [
              {
                name = "CF_API_TOKEN";
                valueFrom.secretKeyRef = {
                  name = "cloudflare-external-dns-token";
                  key = "token";
                };
              }
            ];

            extraArgs = [
              "--cloudflare-proxied"
              "--label-filter=home-ops.dev/public-dns=true"
            ];
          };
        };

        resources.externalSecrets.cloudflare-external-dns-token.spec = {
          secretStoreRef = {
            name = "onepassword";
            kind = "ClusterSecretStore";
          };
          target.name = "cloudflare-external-dns-token";
          data = [
            {
              secretKey = "token";
              remoteRef.key = "cloudflare-external-dns-token/credentials/token";
            }
          ];
        };
      };
    };
}
