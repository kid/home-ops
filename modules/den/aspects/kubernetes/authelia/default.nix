_: {
  den.aspects.kubernetes.authelia.k8s-manifests =
    { charts, cluster, ... }:
    let
      # The chart only mounts its own known keys from authelia-secrets, so the rest live in authelia-extra.
      extraDir = "/secrets/authelia-extra";
      onepassword = {
        name = "onepassword";
        kind = "ClusterSecretStore";
      };
    in
    {
      applications.authelia = {
        namespace = "authelia";
        createNamespace = true;

        helm.releases.authelia = {
          chart = charts.authelia.authelia;
          # The values schema $refs https://charts.authelia.com/definitions.json, unreachable in the Nix sandbox.
          extraOpts = [ "--skip-schema-validation" ];
          values = {
            # The chart defaults to a DaemonSet. Recreate: the SQLite volume is ReadWriteOnce.
            pod = {
              kind = "Deployment";
              strategy.type = "Recreate";
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
              notifier.filesystem.enabled = true;

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
                    claims_policy = "oidc-id-token";
                  }
                  {
                    client_id = "kubernetes";
                    client_name = "Kubernetes";
                    public = true;
                    require_pkce = true;
                    pkce_challenge_method = "S256";
                    redirect_uris = [
                      "http://localhost:8000"
                      "http://localhost:18000"
                    ];
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
                ];
              };
            };
          };
        };

        resources.externalSecrets.authelia-secrets = {
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
            ];
          };
        };

        resources.externalSecrets.authelia-extra = {
          metadata.annotations."argocd.argoproj.io/sync-wave" = "-1";
          spec = {
            secretStoreRef = onepassword;
            target = {
              name = "authelia-extra";
              template.data = {
                "oidc.jwks.rsa.key" = "{{ .jwksKey }}";
                # Authelia wants a hash here; $plaintext$ is its prefix for an unhashed secret.
                "oidc.client.argocd.secret" = ''{{ printf "$plaintext$%s" .argocdClientSecret }}'';
                "users_database.yml" = "{{ .usersDatabase }}";
              };
            };
            data = [
              {
                secretKey = "jwksKey";
                remoteRef.key = "authelia/secrets/oidc-jwks-key";
              }
              {
                secretKey = "argocdClientSecret";
                remoteRef.key = "authelia/secrets/argocd-client-secret";
              }
              {
                secretKey = "usersDatabase";
                remoteRef.key = "authelia/secrets/users-database";
              }
            ];
          };
        };

        resources.snapshotPolicies.authelia.spec = {
          repository = {
            kind = "ClusterRepository";
            name = "r2";
          };
          credentialProjection.enabled = true;
          sources = [ { pvc.name = "authelia"; } ];
          identity = {
            username = "authelia";
            hostname = "authelia";
          };
          retention = {
            keepDaily = 14;
            keepWeekly = 4;
          };
        };

        resources.snapshotSchedules.authelia.spec = {
          policyRef.name = "authelia";
          schedule = {
            cron = "H * * * *";
            jitter = "5m";
            runOnCreate = false;
          };
        };

        resources.restores.authelia.spec = {
          source.fromPolicy = {
            name = "authelia";
            offset = 0;
          };
          target.populator = { };
          policy.onMissingSnapshot = "Continue";
          credentialProjection.enabled = true;
        };

        resources.persistentVolumeClaims.authelia.spec = {
          storageClassName = "miroir";
          accessModes = [ "ReadWriteOnce" ];
          resources.requests.storage = "1Gi";
          dataSourceRef = {
            apiGroup = "kopiur.home-operations.com";
            kind = "Restore";
            name = "authelia";
          };
        };

        resources.httpRoutes.authelia.spec = {
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
}
