# Kanidm (https://kanidm.com), run by the kaniop operator
# (https://github.com/pando85/kaniop): the operator, the one `Kanidm`
# instance, its persons/groups, TLS, routing and backups. Persons, groups and
# OAuth2 clients may live in any namespace (the `*NamespaceSelector`s below);
# other aspects point them at cluster.methods.kanidm.ref.
{ config, ... }:
let
  domain = config.den.clusters.prd.methods.mkAppHostname "idm";
  origin = "https://${domain}";
in
{
  den.clusters.prd.methods.kanidm = {
    inherit domain origin;
    ref = {
      name = "idm";
      namespace = "kanidm";
    };
    # Kanidm gives each OAuth2 client its own issuer.
    issuer = clientId: "${origin}/oauth2/openid/${clientId}";
  };

  den.aspects.kubernetes.kanidm.k8s-manifests =
    {
      charts,
      generators,
      cluster,
      lib,
      ...
    }:
    let
      inherit (cluster.methods.kanidm) ref;
      inherit (ref) namespace;
      # The image's own kanidm user. The kopiur mover reads the volume as this same uid.
      appId = 389;
      # renovate: datasource=docker depName=docker.io/kanidm/server
      serverTag = "1.11.2@sha256:e45f00bd354c1fc1c06a4be484b4e87b094c431e78280f1d19e911815e63efb5";
      # kaniop derives the mail sender image from the server image by
      # swapping /server: for /tools:, which keeps the server's digest.
      # renovate: datasource=docker depName=docker.io/kanidm/tools
      toolsTag = "1.11.2@sha256:144783fc589ac9611f6149f54f95d0d9472c1bf6078e7ed5781be441bcca7d24";
      smtpUser = "arnaud.rebts@gmail.com";
      tlsSecretName = "${ref.name}-tls";
      serviceHostname = "${ref.name}.${namespace}.svc.cluster.local";
      # kaniop names the StatefulSet <Kanidm>-<replica group> and its
      # volumeClaimTemplate kanidm-data (libs/operator/src/kanidm/reconcile/statefulset.rs).
      replicaGroup = "default";
      dataClaim = "kanidm-data-${ref.name}-${replicaGroup}-0";
      backupName = "kanidm";
      clusterCa = {
        name = "cluster-ca";
        kind = "ClusterIssuer";
        group = "cert-manager.io";
      };
      kanidmLabels = {
        "app.kubernetes.io/name" = "kanidm";
        "kanidm.kaniop.rs/cluster" = ref.name;
      };
      operatorLabels = component: {
        "app.kubernetes.io/name" = "kaniop";
        "app.kubernetes.io/component" = component;
      };
      # After the operator's wave is Healthy: its webhook (failurePolicy Fail)
      # must serve before persons and groups are created.
      afterOperator."argocd.argoproj.io/sync-wave" = "1";
      # kaniop creates the `idm` Service from the Kanidm resource (wave 1).
      # ArgoCD waits for the route and its BackendTLSPolicy to be Healthy,
      # which needs that Service, so they must sync after it.
      afterKanidm."argocd.argoproj.io/sync-wave" = "2";
      mfaGroup = {
        kanidmRef.name = ref.name;
        members = [ "kid" ];
        # Passkey, or password + TOTP.
        accountPolicy.credentialTypeMinimum = "mfa";
      };
    in
    {
      nixidy.applicationImports = [
        (generators.fromChartCRDModule {
          name = "kaniop";
          chart = charts.pando85.kaniop;
          kindFilter = [
            "Kanidm"
            "KanidmGroup"
            "KanidmPersonAccount"
            "KanidmOAuth2Client"
          ];
        })
      ];

      applications.kanidm = {
        inherit namespace;

        helm.releases.kaniop = {
          chart = charts.pando85.kaniop;
          values = {
            # Both are Helm pre-install hooks. ArgoCD already applies the
            # chart's crds/ on every sync, and the migration only concerns
            # upgrades from before 0.19; it also stamps `now` into its
            # manifest, which would break checks.manifests.
            crdApply.enabled = false;
            crdMigration.personAccountPlural.enabled = false;

            metrics = {
              enabled = true;
              serviceMonitor.enabled = true;
            };

            resources = {
              requests = {
                cpu = "10m";
                memory = "64Mi";
              };
              limits.memory = "256Mi";
            };

            # Rejects a second CR managing the same Kanidm entry, which the
            # any-namespace selectors below make possible. Its cert comes from
            # cert-manager, not from the chart's random-cert Job.
            webhook = {
              enabled = true;
              certManager = {
                enabled = true;
                # The chart's schema takes no group.
                issuerRef = { inherit (clusterCa) name kind; };
              };
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

        resources =
          cluster.methods.mkKopiurBackup {
            name = backupName;
            uid = appId;
            existingClaim = dataClaim;
          }
          // {
            # With issuerRef set the chart creates no root CA Certificate, but
            # still points the CA injection at one. The webhook cert's own
            # Secret carries the cluster-ca as ca.crt.
            validatingWebhookConfigurations.kaniop-webhook.metadata.annotations."cert-manager.io/inject-ca-from" =
              lib.mkForce "${namespace}/kaniop-webhook-cert";

            ciliumNetworkPolicies = with cluster.methods.netpol; {
              kaniop-operator = mkPolicy (operatorLabels "operator") {
                ingress = [ (scrapeIngress [ 8080 ]) ];
                egress = [
                  apiserverEgress
                  (toPods kanidmLabels [ 8443 ])
                ];
              };
              kaniop-webhook = mkPolicy (operatorLabels "webhook") {
                ingress = [ (webhookIngress 8443) ];
                egress = [ apiserverEgress ];
              };
              kanidm = mkPolicy kanidmLabels {
                ingress = [
                  (gatewayIngress 8443)
                  (fromPods (operatorLabels "operator") [ 8443 ])
                ];
              };
              # Reaches Kanidm at its origin, so through the apps Gateway.
              kanidm-mail-sender = mkPolicy { "app.kubernetes.io/name" = "kanidm-mail-sender"; } {
                egress = [
                  gatewayEgress
                  (fqdnEgress [ "smtp.gmail.com" ] [ 587 ])
                ];
              };
            };

            kanidms.${ref.name} = {
              metadata.annotations = afterOperator;
              spec = {
                inherit domain origin tlsSecretName;
                image = "docker.io/kanidm/server:${serverTag}";
                replicaGroups = [
                  {
                    name = replicaGroup;
                    replicas = 1;
                    resources = {
                      requests = {
                        cpu = "50m";
                        memory = "128Mi";
                      };
                      limits.memory = "512Mi";
                    };
                  }
                ];

                # Persons, groups, OAuth2 clients and service accounts from any namespace.
                personNamespaceSelector = { };
                groupNamespaceSelector = { };
                oauth2ClientNamespaceSelector = { };
                serviceAccountNamespaceSelector = { };

                env = [
                  # Only Envoy and the operator reach the pod (netpol above), so
                  # every X-Forwarded-For source is a trusted one. The env var
                  # has no per-CIDR form, that needs a server.toml.
                  {
                    name = "KANIDM_TRUST_X_FORWARDED_FOR";
                    value = "true";
                  }
                  # Daily online backups next to the database, so kopiur's
                  # snapshots of the volume carry consistent dumps too.
                  {
                    name = "KANIDM_ONLINE_BACKUP_PATH";
                    value = "/data/backups";
                  }
                  {
                    name = "KANIDM_ONLINE_BACKUP_SCHEDULE";
                    value = "00 03 * * *";
                  }
                  {
                    name = "KANIDM_ONLINE_BACKUP_VERSIONS";
                    value = "7";
                  }
                ];

                storage.volumeClaimTemplate.spec = {
                  storageClassName = "miroir";
                  accessModes = [ "ReadWriteOnce" ];
                  resources.requests.storage = "1Gi";
                  dataSourceRef = {
                    apiGroup = "kopiur.home-operations.com";
                    kind = "Restore";
                    name = backupName;
                  };
                };

                # kaniop's documented PSA-restricted settings.
                securityContext = {
                  runAsNonRoot = true;
                  runAsUser = appId;
                  runAsGroup = appId;
                  fsGroup = appId;
                  fsGroupChangePolicy = "OnRootMismatch";
                  seccompProfile.type = "RuntimeDefault";
                };
                containers = [
                  {
                    name = "kanidm";
                    securityContext = {
                      allowPrivilegeEscalation = false;
                      capabilities.drop = [ "ALL" ];
                    };
                  }
                ];
                automountServiceAccountToken = false;

                # Gmail with an app password, put in 1Password by terragrunt.nix.
                mailSender = {
                  relay = "smtp://smtp.gmail.com:587";
                  credentialsSecret.name = "kanidm-smtp";
                  fromAddress = smtpUser;
                  image = "docker.io/kanidm/tools:${toolsTag}";
                  resources = {
                    requests = {
                      cpu = "10m";
                      memory = "16Mi";
                    };
                    limits.memory = "64Mi";
                  };
                };
              };
            };

            kanidmPersonAccounts.kid = {
              metadata.annotations = afterOperator;
              spec = {
                kanidmRef.name = ref.name;
                personAttributes = {
                  displayname = "Arnaud Rebts";
                  mail = [ smtpUser ];
                };
              };
            };

            kanidmGroups = {
              admins = {
                metadata.annotations = afterOperator;
                spec = mfaGroup;
              };
              media = {
                metadata.annotations = afterOperator;
                spec = mfaGroup;
              };
            };

            certificates.${tlsSecretName}.spec = {
              secretName = tlsSecretName;
              dnsNames = [
                domain
                ref.name
                serviceHostname
              ];
              # PKCS#8 is the key format Kanidm documents.
              privateKey = {
                algorithm = "ECDSA";
                size = 256;
                encoding = "PKCS8";
              };
              issuerRef = clusterCa;
            };

            # cluster-ca ConfigMap comes from trust-manager/default.nix's Bundle.
            backendTLSPolicies.${ref.name} = {
              metadata.annotations = afterKanidm;
              spec = {
                targetRefs = [
                  {
                    kind = "Service";
                    inherit (ref) name;
                    group = "";
                  }
                ];
                validation = {
                  hostname = serviceHostname;
                  caCertificateRefs = [
                    {
                      kind = "ConfigMap";
                      name = "cluster-ca";
                      group = "";
                    }
                  ];
                };
              };
            };

            httpRoutes.${ref.name} = {
              metadata.annotations = afterKanidm;
              spec = {
                parentRefs = [
                  {
                    group = "gateway.networking.k8s.io";
                    kind = "Gateway";
                    name = "apps";
                    namespace = "envoy-gateway-system";
                    sectionName = "https";
                  }
                ];
                hostnames = [ domain ];
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
                        inherit (ref) name;
                        port = 8443;
                        weight = 1;
                      }
                    ];
                  }
                ];
              };
            };

            # The Gmail app password from terragrunt.nix's 1Password item.
            externalSecrets.kanidm-smtp = {
              metadata.annotations."argocd.argoproj.io/sync-wave" = "-1";
              spec = {
                secretStoreRef = {
                  name = "onepassword";
                  kind = "ClusterSecretStore";
                };
                target = {
                  name = "kanidm-smtp";
                  template.data = {
                    username = smtpUser;
                    password = "{{ .password }}";
                  };
                };
                data = [
                  {
                    secretKey = "password";
                    remoteRef.key = "kanidm/secrets/smtp-password";
                  }
                ];
              };
            };
          };
      };
    };
}
