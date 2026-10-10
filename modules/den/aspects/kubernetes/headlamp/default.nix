# Headlamp dashboard with the Argo CD plugin, public through the Cloudflare tunnel.
# Users log in through Authelia with the same client kubectl uses (cluster.methods.kubeLogin), so
# the ID token Headlamp forwards is one the API server already accepts and RBAC applies per user;
# Headlamp's own ServiceAccount gets no cluster role.
_: {
  den.aspects.kubernetes.headlamp.k8s-manifests =
    { charts, cluster, ... }:
    let
      hostname = cluster.methods.mkAppHostname "headlamp";
      login = cluster.methods.kubeLogin;
      callbackURL = "https://${hostname}/oidc-callback";
    in
    {
      applications.headlamp = {
        namespace = "headlamp";

        helm.releases.headlamp = {
          chart = charts.kubernetes-sigs.headlamp;
          values = {
            clusterRoleBinding.create = false;

            config.oidc = {
              secret.create = false;
              # The chart reads every OIDC_* variable from this Secret (envFrom).
              externalSecret = {
                enabled = true;
                name = "headlamp-oidc";
                hasScopes = true;
              };
              # Only switches on the matching flags; the values come from the Secret.
              inherit callbackURL;
            };

            # Sidecar that installs the plugins from Artifact Hub into the shared plugins dir.
            pluginsManager = {
              enabled = true;
              version = "0.1.1";
              configContent = builtins.toJSON {
                plugins = [
                  {
                    name = "argocd";
                    source = "https://artifacthub.io/packages/headlamp/headlamp-plugins/headlamp_argocd";
                    version = "0.1.0-alpha";
                  }
                ];
              };
              resources = {
                requests = {
                  cpu = "10m";
                  memory = "64Mi";
                };
                limits.memory = "256Mi";
              };
            };

            resources = {
              requests = {
                cpu = "10m";
                memory = "64Mi";
              };
              limits.memory = "256Mi";
            };
          };
        };

        resources = {
          externalSecrets.headlamp-oidc = {
            metadata.annotations."argocd.argoproj.io/sync-wave" = "-1";
            spec = {
              secretStoreRef = {
                name = "onepassword";
                kind = "ClusterSecretStore";
              };
              target = {
                name = "headlamp-oidc";
                template.data = {
                  OIDC_CLIENT_ID = login.clientId;
                  OIDC_CLIENT_SECRET = "{{ .clientSecret }}";
                  OIDC_ISSUER_URL = login.issuerUrl;
                  # groups is what the API server maps to RBAC (kubeLogin.group); offline_access gets a refresh token.
                  OIDC_SCOPES = "profile,email,groups,offline_access";
                  OIDC_CALLBACK_URL = callbackURL;
                };
              };
              data = [
                {
                  secretKey = "clientSecret";
                  remoteRef.key = "authelia/secrets/kubelogin-client-secret";
                }
              ];
            };
          };

          ciliumNetworkPolicies = with cluster.methods.netpol; {
            headlamp = mkPolicy { "app.kubernetes.io/name" = "headlamp"; } {
              ingress = [ (tunnelIngress 4466) ];
              egress = [
                apiserverEgress
                (fqdnEgress
                  [
                    # OIDC discovery and token exchange.
                    (cluster.methods.mkAppHostname "auth")
                    # pluginctl (npx) and the plugin download it resolves through Artifact Hub.
                    "registry.npmjs.org"
                    "artifacthub.io"
                    "github.com"
                    "objects.githubusercontent.com"
                    "release-assets.githubusercontent.com"
                  ]
                  [ 443 ]
                )
              ];
            };
          };

          httpRoutes.headlamp.metadata.labels."home-ops.dev/public-dns" = "true";
          httpRoutes.headlamp.spec = {
            parentRefs = [
              {
                group = "gateway.networking.k8s.io";
                kind = "Gateway";
                name = "cloudflare-tunnel";
                namespace = "cloudflare-tunnel-system";
                sectionName = "http";
              }
            ];
            hostnames = [ hostname ];
            rules = [
              {
                matches = [
                  {
                    path = {
                      type = "PathPrefix";
                      value = "/";
                    };
                  }
                ];
                backendRefs = [
                  {
                    group = "";
                    kind = "Service";
                    name = "headlamp";
                    port = 80;
                    weight = 1;
                  }
                ];
              }
            ];
          };
        };
      };
    };
}
