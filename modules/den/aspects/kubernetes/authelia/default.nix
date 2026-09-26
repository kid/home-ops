_: {
  den.aspects.kubernetes.authelia.k8s-manifests =
    { charts, cluster, ... }:
    let
      # The chart only mounts its own known keys from authelia-secrets, so the rest live in authelia-extra.
      extraDir = "/secrets/authelia-extra";
      smtpUser = "arnaud.rebts@gmail.com";
      # The image runs as root by default. The kopiur mover reads the volume as this same uid.
      appId = 1000;
      onepassword = {
        name = "onepassword";
        kind = "ClusterSecretStore";
      };
    in
    {
      applications.authelia = {
        namespace = "authelia";

        helm.releases.authelia = {
          chart = charts.authelia.authelia;
          # The values schema $refs https://charts.authelia.com/definitions.json, unreachable in the Nix sandbox.
          extraOpts = [ "--skip-schema-validation" ];
          values = {
            # The chart defaults to a DaemonSet. Recreate: the SQLite volume is ReadWriteOnce.
            pod = {
              kind = "Deployment";
              strategy.type = "Recreate";
              securityContext.pod = {
                runAsNonRoot = true;
                runAsUser = appId;
                runAsGroup = appId;
                fsGroup = appId;
                fsGroupChangePolicy = "OnRootMismatch";
              };
            };

            persistence = {
              enabled = true;
              existingClaim = "authelia";
            };

            # The chart generates random secrets otherwise, and a helm template render is not idempotent.
            secret = {
              existingSecret = "authelia-secrets";
              additionalSecrets.authelia-extra = { };
            };

            configMap = {
              session.cookies = [
                {
                  inherit (cluster) domain;
                  subdomain = "auth";
                }
              ];

              storage.local.enabled = true;

              # Gmail with an app password, put in 1Password by the authelia tf stack. No startup check: a mail outage must not stop the login for everything.
              notifier = {
                disable_startup_check = true;
                smtp = {
                  enabled = true;
                  address = "submission://smtp.gmail.com:587";
                  username = smtpUser;
                  sender = "Authelia <${smtpUser}>";
                };
              };

              # Users live in 1Password, so Authelia's own password change/reset would write to a read-only file.
              authentication_backend = {
                password_reset.disable = true;
                password_change.disable = true;
                file = {
                  enabled = true;
                  path = "${extraDir}/users_database.yml";
                };
              };

              identity_providers.oidc = {
                enabled = true;
                jwks = [ { key.path = "${extraDir}/oidc.jwks.rsa.key"; } ];

                # Authelia 4.39 leaves these claims out of the ID token unless a policy adds them.
                claims_policies.oidc-id-token.id_token = [
                  "groups"
                  "email"
                  "email_verified"
                  "alt_emails"
                  "preferred_username"
                  "name"
                ];

                clients = [
                  {
                    client_id = "argocd";
                    client_name = "ArgoCD";
                    client_secret.path = "${extraDir}/oidc.client.argocd.secret";
                    redirect_uris = [ "https://${cluster.methods.mkAppHostname "argocd"}/auth/callback" ];
                    claims_policy = "oidc-id-token";
                  }
                  {
                    client_id = "argocd-cli";
                    client_name = "ArgoCD CLI";
                    public = true;
                    require_pkce = true;
                    pkce_challenge_method = "S256";
                    redirect_uris = [ "http://localhost:8085/auth/callback" ];
                    # The CLI asks for offline_access whenever the provider lists it.
                    scopes = [
                      "openid"
                      "profile"
                      "email"
                      "groups"
                      "offline_access"
                    ];
                    grant_types = [
                      "authorization_code"
                      "refresh_token"
                    ];
                    claims_policy = "oidc-id-token";
                  }
                  {
                    client_id = cluster.methods.kubeLogin.clientId;
                    client_name = "Kubernetes";
                    client_secret.path = "${extraDir}/oidc.client.kubelogin.secret";
                    redirect_uris = [
                      "http://localhost:8000"
                      "http://localhost:18000"
                    ];
                    # Authelia's kubelogin page (integration/openid-connect/clients/kubelogin) plus offline_access
                    # and refresh_token, without which the login expires with the ID token after an hour.
                    scopes = [
                      "openid"
                      "groups"
                      "email"
                      "profile"
                      "offline_access"
                    ];
                    grant_types = [
                      "authorization_code"
                      "refresh_token"
                    ];
                    claims_policy = "oidc-id-token";
                  }
                  {
                    client_id = "grafana";
                    client_name = "Grafana";
                    client_secret.path = "${extraDir}/oidc.client.grafana.secret";
                    redirect_uris = [ "https://${cluster.methods.mkAppHostname "grafana"}/login/generic_oauth" ];
                    claims_policy = "oidc-id-token";
                  }
                ];
              };
            };
          };
        };

        resources =
          cluster.methods.mkKopiurBackup {
            name = "authelia";
            uid = appId;
          }
          // {
            externalSecrets.authelia-secrets = {
              metadata.annotations."argocd.argoproj.io/sync-wave" = "-1";
              spec = {
                secretStoreRef = onepassword;
                target.name = "authelia-secrets";
                data = [
                  {
                    secretKey = "identity_validation.reset_password.jwt.hmac.key";
                    remoteRef.key = "authelia/secrets/reset-password-jwt-secret";
                  }
                  {
                    secretKey = "session.encryption.key";
                    remoteRef.key = "authelia/secrets/session-encryption-key";
                  }
                  {
                    secretKey = "storage.encryption.key";
                    remoteRef.key = "authelia/secrets/storage-encryption-key";
                  }
                  {
                    secretKey = "identity_providers.oidc.hmac.key";
                    remoteRef.key = "authelia/secrets/oidc-hmac-secret";
                  }
                  {
                    secretKey = "notifier.smtp.password.txt";
                    remoteRef.key = "authelia/secrets/smtp-password";
                  }
                ];
              };
            };

            externalSecrets.authelia-extra = {
              metadata.annotations."argocd.argoproj.io/sync-wave" = "-1";
              spec = {
                secretStoreRef = onepassword;
                target = {
                  name = "authelia-extra";
                  template.data = {
                    "oidc.jwks.rsa.key" = "{{ .jwksKey }}";
                    # Authelia wants a hash here; $plaintext$ is its prefix for an unhashed secret.
                    "oidc.client.argocd.secret" = ''{{ printf "$plaintext$%s" .argocdClientSecret }}'';
                    "oidc.client.kubelogin.secret" = ''{{ printf "$plaintext$%s" .kubeloginClientSecret }}'';
                    "oidc.client.grafana.secret" = ''{{ printf "$plaintext$%s" .grafanaClientSecret }}'';
                    "users_database.yml" = "{{ .usersDatabase }}";
                  };
                };
                data = [
                  {
                    secretKey = "jwksKey";
                    remoteRef = {
                      key = "authelia/secrets/oidc-jwks-key";
                      decodingStrategy = "Base64";
                    };
                  }
                  {
                    secretKey = "argocdClientSecret";
                    remoteRef.key = "authelia/secrets/argocd-client-secret";
                  }
                  {
                    secretKey = "kubeloginClientSecret";
                    remoteRef.key = "authelia/secrets/kubelogin-client-secret";
                  }
                  {
                    secretKey = "grafanaClientSecret";
                    remoteRef.key = "authelia/secrets/grafana-client-secret";
                  }
                  {
                    secretKey = "usersDatabase";
                    remoteRef = {
                      key = "authelia/secrets/users-database";
                      decodingStrategy = "Base64";
                    };
                  }
                ];
              };
            };

            httpRoutes.authelia.spec = {
              parentRefs = [
                {
                  group = "gateway.networking.k8s.io";
                  kind = "Gateway";
                  name = "apps";
                  namespace = "envoy-gateway-system";
                  sectionName = "https";
                }
              ];
              hostnames = [ (cluster.methods.mkAppHostname "auth") ];
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
                      name = "authelia";
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
