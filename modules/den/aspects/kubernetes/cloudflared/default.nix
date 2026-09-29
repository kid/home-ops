_: {
  den.aspects.kubernetes.cloudflared.k8s-manifests =
    {
      charts,
      cluster,
      ...
    }:
    {
      applications.cloudflare-tunnel-gateway = {
        namespace = "cloudflare-tunnel-system";

        helm.releases.cloudflare-tunnel-gateway-controller = {
          chart = charts.lexfrei.cloudflare-tunnel-gateway-controller;
          values = {
            gatewayClassConfig = {
              create = true;
              tunnelID = cluster.cloudflare.tunnelId;
              cloudflareCredentialsSecretRef.name = "cloudflare-tunnel-api-token";
            };
            proxy.tunnelTokenSecretRef.name = "cloudflare-tunnel-connector-token";
          };
        };

        resources = {
          externalSecrets.cloudflare-tunnel-api-token.spec = {
            secretStoreRef = {
              name = "onepassword";
              kind = "ClusterSecretStore";
            };
            target.name = "cloudflare-tunnel-api-token";
            data = [
              {
                secretKey = "api-token";
                remoteRef.key = "cloudflared-tunnel-credentials/credentials/api-token";
              }
            ];
          };

          externalSecrets.cloudflare-tunnel-connector-token.spec = {
            secretStoreRef = {
              name = "onepassword";
              kind = "ClusterSecretStore";
            };
            target.name = "cloudflare-tunnel-connector-token";
            data = [
              {
                secretKey = "tunnel-token";
                remoteRef.key = "cloudflared-tunnel-credentials/credentials/tunnel-token";
              }
            ];
          };

          gateways.cloudflare-tunnel.spec = {
            gatewayClassName = "cloudflare-tunnel";
            listeners = [
              {
                name = "http";
                protocol = "HTTP";
                port = 80;
              }
            ];
          };
        };
      };
    };
}
