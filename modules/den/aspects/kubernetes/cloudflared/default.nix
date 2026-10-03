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
            # limits.cpu = null drops the chart's default CPU limit.
            resources = {
              requests = {
                cpu = "10m";
                memory = "128Mi";
              };
              limits = {
                cpu = null;
                memory = "256Mi";
              };
            };
            proxy.resources = {
              requests = {
                cpu = "10m";
                memory = "64Mi";
              };
              limits = {
                cpu = null;
                memory = "128Mi";
              };
            };
          };
        };

        resources = {
          ciliumNetworkPolicies =
            with cluster.methods.netpol;
            let
              proxy = {
                "app.kubernetes.io/name" = "cloudflare-tunnel-gateway-controller-proxy";
              };
            in
            {
              cloudflare-tunnel-gateway-controller =
                mkPolicy { "app.kubernetes.io/name" = "cloudflare-tunnel-gateway-controller"; }
                  {
                    egress = [
                      apiserverEgress
                      (fqdnEgress [ "api.cloudflare.com" ] [ 443 ])
                      (toPods proxy [ 8081 ])
                    ];
                  };
              cloudflare-tunnel-gateway-controller-proxy = mkPolicy proxy {
                egress = [
                  {
                    toEntities = [ "world" ];
                    toPorts = tcpUdp [ 7844 ];
                  }
                  clusterEgress
                ];
              };
            };

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
                allowedRoutes.namespaces.from = "All";
              }
            ];
          };
        };
      };
    };
}
