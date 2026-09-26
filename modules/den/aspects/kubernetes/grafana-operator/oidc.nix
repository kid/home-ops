# Log in through Authelia (kubernetes/authelia/default.nix defines the
# "grafana" client). Separate from default.nix so that file doesn't
# hard-depend on Authelia or External Secrets being present.
_: {
  den.aspects.kubernetes.grafana-oidc.k8s-manifests =
    { cluster, ... }:
    {
      applications.grafana-operator = {
        resources.grafanas.grafana.spec = {
          config."auth.generic_oauth" = {
            enabled = "true";
            name = "Authelia";
            client_id = "grafana";
            # client_secret comes in via GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET below —
            # Grafana maps GF_<SECTION>_<KEY> env vars onto config automatically.
            auth_url = "https://${cluster.methods.mkAppHostname "auth"}/api/oidc/authorization";
            token_url = "https://${cluster.methods.mkAppHostname "auth"}/api/oidc/token";
            api_url = "https://${cluster.methods.mkAppHostname "auth"}/api/oidc/userinfo";
            scopes = "openid profile email groups";
          };

          deployment.spec.template.spec.containers = [
            {
              name = "grafana";
              env = [
                {
                  name = "GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET";
                  valueFrom.secretKeyRef = {
                    name = "grafana-oidc";
                    key = "clientSecret";
                  };
                }
              ];
            }
          ];
        };

        resources.externalSecrets.grafana-oidc = {
          metadata.annotations."argocd.argoproj.io/sync-wave" = "-1";
          spec = {
            secretStoreRef = {
              name = "onepassword";
              kind = "ClusterSecretStore";
            };
            target.name = "grafana-oidc";
            data = [
              {
                secretKey = "clientSecret";
                remoteRef.key = "authelia/secrets/grafana-client-secret";
              }
            ];
          };
        };
      };
    };
}
