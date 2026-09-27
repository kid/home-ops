# lexfrei/cloudflare-tunnel-gateway-controller: a Gateway API controller for
# Cloudflare Tunnel (github.com/lexfrei/cloudflare-tunnel-gateway-controller).
# It's purely the public front door — apps that want to be reachable from the
# internet add their own HTTPRoute here (parentRefs -> the "cloudflare-tunnel"
# Gateway below), always forwarding into Envoy Gateway's internal proxy
# Service, so Authelia forward-auth and native-OIDC apps keep enforcing
# exactly as they do for LAN traffic. See argocd/default.nix for a worked
# example.
_: {
  den.aspects.kubernetes.cloudflared.k8s-manifests =
    {
      lib,
      charts,
      cluster,
      ...
    }:
    {
      # Renders nothing until the one-time bootstrap terragrunt apply has
      # happened and its tunnel_id output is copied into
      # cluster.cloudflare.tunnelId — see cloudflared/terragrunt.nix.
      applications.cloudflare-tunnel-gateway = lib.mkIf (cluster.cloudflare.tunnelId != null) {
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

          # Shared, public-facing Gateway. Deliberately no hostnames/routes
          # here — each app opts in from its own file (see argocd/default.nix).
          # Cloudflare terminates TLS at its own edge; traffic arrives at the
          # proxy over the tunnel already decrypted, so this is a plain HTTP
          # listener, not a second TLS termination point.
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
