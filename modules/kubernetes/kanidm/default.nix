# Kanidm (https://kanidm.com), run by the kaniop operator
# (https://github.com/pando85/kaniop): the operator, the one `Kanidm`
# instance, its persons/groups, TLS, routing and backups. Every
# den.accessGroups group labelled `oauth-grant` becomes a Kanidm group
# (`mfa`-labelled ones require MFA), and every registry user the cluster's
# login gates admit a person (den.users.registry.<user>.{displayName,mail});
# see modules/den/policies/users.nix.
# Persons, groups and OAuth2 clients may live in any namespace (the
# `*NamespaceSelector`s below); other aspects point them at
# cluster.methods.kanidm.ref.
{ acl, config, ... }:
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
      # Registry users the cluster's gates (its environment's plus its own)
      # admit, each with the closure of its groups.
      persons =
        config.den.users.registry
        |> lib.filterAttrs (_: acl.admits (acl.gatesFor cluster))
        |> lib.mapAttrs (_: u: u // { allGroups = acl.closure u.groups; });
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

      applications.kaniop = {
        inherit namespace;
        # Its webhook's certificate.
        flux.dependsOn = [ "cert-manager" ];

        helm.releases.kaniop = {
          chart = charts.pando85.kaniop;
          values = {
            # Both are Helm pre-install hooks. The chart's crds/ are rendered
            # with the rest, and the migration only concerns upgrades from
            # before 0.19; it also stamps `now` into its manifest, which would
            # break checks.manifests.
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

        resources = {
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
          };
        };
      };

      # Separate from the operator: its webhook must serve before these are
      # applied. The volume restores from the kopiur repository.
      applications.kanidm = {
        inherit namespace;
        flux.dependsOn = [
          "kaniop"
          "kopiur-config"
          "cert-manager"
        ];

        resources =
          cluster.methods.mkKopiurBackup {
            name = backupName;
            uid = appId;
            existingClaim = dataClaim;
          }
          // {
            ciliumNetworkPolicies.kanidm =
              with cluster.methods.netpol;
              mkPolicy kanidmLabels {
                ingress = [
                  (gatewayIngress 8443)
                  (fromPods (operatorLabels "operator") [ 8443 ])
                ];
              };

            kanidms.${ref.name} = {
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
              };
            };

            kanidmPersonAccounts = lib.mapAttrs (_: u: {
              spec = {
                kanidmRef.name = ref.name;
                personAttributes = {
                  displayname = u.displayName;
                }
                // lib.optionalAttrs (u.mail != [ ]) { inherit (u) mail; };
              };
            }) persons;

            kanidmGroups =
              lib.genAttrs (config.den.accessGroups |> builtins.attrNames |> acl.labelled "oauth-grant")
                (group: {
                  spec = {
                    kanidmRef.name = ref.name;
                    members = persons |> lib.filterAttrs (_: u: lib.elem group u.allGroups) |> builtins.attrNames;
                  }
                  // lib.optionalAttrs (acl.labelled "mfa" [ group ] != [ ]) {
                    # Passkey, or password + TOTP.
                    accountPolicy.credentialTypeMinimum = "mfa";
                  };
                });

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
          };
      };
    };
}
