_: {
  den.aspects.kubernetes.authelia.k8s-manifests =
    {
      charts,
      generators,
      cluster,
      ...
    }:
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
      valkeyLabels."app.kubernetes.io/name" = "authelia-valkey";
      # renovate: datasource=docker depName=docker.io/valkey/valkey
      valkeyTag = "9.1.2@sha256:418652cfb58ef879d4978c33553735d7147016032d5aefaa14c828e611eb9dfd";
      # The consent page then has a "remember" checkbox, instead of a prompt at each login.
      rememberConsent = {
        consent_mode = "pre-configured";
        pre_configured_consent_duration = "1 year";
      };
    in
    {
      # SecurityPolicy types, for kanidm/envoy-oidc.nix's cluster.methods.mkOidcAuth
      # — charts.envoyproxy.gateway-helm is already pinned and installed with
      # crds.enabled = true by envoy-gateway/default.nix.
      nixidy.applicationImports = [
        (generators.fromChartCRDModule {
          name = "envoy-gateway-security-policy";
          chart = charts.envoyproxy.gateway-helm;
          kindFilter = [ "SecurityPolicy" ];
        })
      ];

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
              resources = {
                requests = {
                  cpu = "10m";
                  memory = "64Mi";
                };
                limits.memory = "128Mi";
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
              telemetry.metrics = {
                enabled = true;
                serviceMonitor.enabled = true;
              };

              # The pod's clock is the node's, which is already synchronized;
              # the check would need NTP egress to time.cloudflare.com.
              ntp.disable_startup_check = true;

              session = {
                inactivity = "1 week";
                expiration = "1 month";
                cookies = [
                  {
                    inherit (cluster) domain;
                    subdomain = "auth";
                  }
                ];
                # Without it the sessions are in memory, lost at each restart. No password: only the authelia pod reaches it.
                redis = {
                  enabled = true;
                  host = "authelia-valkey";
                  password.disabled = true;
                };
              };

              storage.local.enabled = true;

              access_control.default_policy = "two_factor";

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
                lifespans.refresh_token = "30 days";

                # Authelia 4.39 leaves these claims out of the ID token unless a policy adds them.
                claims_policies.oidc-id-token.id_token = [
                  "groups"
                  "email"
                  "email_verified"
                  "alt_emails"
                  "preferred_username"
                  "name"
                ];

                clients = map (client: client // rememberConsent) [
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
            ciliumNetworkPolicies = with cluster.methods.netpol; {
              authelia = mkPolicy { "app.kubernetes.io/name" = "authelia"; } {
                ingress = [
                  (tunnelIngress 9091)
                  (scrapeIngress [ 9959 ])
                ];
                egress = [
                  (fqdnEgress [ "smtp.gmail.com" ] [ 587 ])
                  (toPods valkeyLabels [ 6379 ])
                ];
              };
              authelia-valkey = mkPolicy valkeyLabels {
                ingress = [ (fromPods { "app.kubernetes.io/name" = "authelia"; } [ 6379 ]) ];
              };
            };

            # Sessions only, so no kopiur backup. The volume keeps them over a Valkey restart.
            statefulSets.authelia-valkey.spec = {
              serviceName = "authelia-valkey";
              selector.matchLabels = valkeyLabels;
              template = {
                metadata.labels = valkeyLabels;
                spec = {
                  securityContext = {
                    runAsNonRoot = true;
                    runAsUser = 999;
                    runAsGroup = 999;
                    fsGroup = 999;
                    fsGroupChangePolicy = "OnRootMismatch";
                  };
                  containers.valkey = {
                    image = "docker.io/valkey/valkey:${valkeyTag}";
                    ports.redis.containerPort = 6379;
                    volumeMounts."/data".name = "data";
                    resources = {
                      requests = {
                        cpu = "10m";
                        memory = "32Mi";
                      };
                      limits.memory = "64Mi";
                    };
                  };
                };
              };
              volumeClaimTemplates = [
                {
                  metadata.name = "data";
                  spec = {
                    storageClassName = "miroir";
                    accessModes = [ "ReadWriteOnce" ];
                    resources.requests.storage = "1Gi";
                  };
                }
              ];
            };

            services.authelia-valkey.spec = {
              selector = valkeyLabels;
              ports.redis = {
                port = 6379;
                targetPort = "redis";
              };
            };

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

            # Public, through the Cloudflare tunnel: it is also the login for apps exposed there.
            httpRoutes.authelia.metadata.labels."home-ops.dev/public-dns" = "true";
            httpRoutes.authelia.spec = {
              parentRefs = [
                {
                  group = "gateway.networking.k8s.io";
                  kind = "Gateway";
                  name = "cloudflare-tunnel";
                  namespace = "cloudflare-tunnel-system";
                  sectionName = "http";
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
