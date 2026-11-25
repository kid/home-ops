# Renovate for every repository of the cluster repo's owner: mogenius'
# renovate-operator discovers them through the Renovate GitHub App and runs one
# executor Job per repository, in the Nix-built image of ./_image.nix. The
# shared config is this repo's .renovate/org-inherited-config.json5, inherited
# ahead of each repo's own. The UI is internal, behind Kanidm; the webhook
# server is public through the Cloudflare tunnel, so the repositories' GitHub
# webhooks start runs straight away: their dashboard and PR checkboxes, and a
# push to a repository another one pins (`/webhook/v1/schedule`). The webhooks
# and their token come from the renovate-webhook Terragrunt stack
# (tf-catalog/modules/renovate-webhook).
_:
let
  namespace = "renovate";
  jobName = "renovate";
  githubSecret = "renovate-github-app";
  webhookSecret = "renovate-webhook-token";
  # 1Password item, in the cluster's vault (section `credentials`), holding
  # the GitHub App; the private key is base64, a PEM is multi-line.
  appItem = "github-renovate-app";
  # Must match tf-catalog/modules/renovate-webhook's token_item.
  webhookItem = "renovate-webhook";
  # Repositories whose GitHub webhook schedules a run.
  repositories = [
    "home-ops"
    "nixfiles-work"
    "neovim"
  ];
  # A push to a key repository moves the rev each listed repository pins
  # (home-ops' modules/apps/neovim.nix), so it schedules their runs. GitHub
  # sends a webhook for a push to any branch.
  pushSchedules = {
    neovim = [ "home-ops" ];
  };

  uiHost = cluster: cluster.methods.mkAppHostname "renovate";
  webhookHost = cluster: cluster.methods.mkAppHostname "renovate-webhook";
  githubRepo =
    cluster: builtins.match "https://github\\.com/([^/]+)/([^.]+)\\.git" cluster.nixidy.repository;
  githubOwner = cluster: builtins.elemAt (githubRepo cluster) 0;
in
{
  den.aspects.kubernetes.renovate = {
    k8s-manifests =
      {
        charts,
        cluster,
        generators,
        images,
        ...
      }:
      let
        globalConfig = {
          binarySource = "global";
          inheritConfig = true;
          inheritConfigRepoName = "${githubOwner cluster}/${builtins.elemAt (githubRepo cluster) 1}";
          inheritConfigFileName = ".renovate/org-inherited-config.json5";
          # A run without the shared config would open PRs with the wrong rules.
          inheritConfigStrict = true;
          # Adopts the hosted App's PRs (gitIgnoredAuthors is the inherited half).
          ignorePrAuthor = true;
          # Minutes per postUpgradeTasks command: write-manifests starts from a cold store.
          executionTimeout = 30;
          allowedCommands = [
            "^refresh-nix-hash [\\w./-]+ [\\w./-]+ [\\w.-]+$"
            "^nix run \\.#rehash-changed-pins$"
            "^nix run \\.#write-manifests -- --skip-secrets$"
            "^nix run \\.#write-flake$"
            "^nix flake lock$"
          ];
          # postUpgradeTasks only get Renovate's basic env vars.
          customEnvVariables = {
            USER = "renovate";
            SSL_CERT_FILE = "/etc/ssl/certs/ca-bundle.crt";
            NIX_SSL_CERT_FILE = "/etc/ssl/certs/ca-bundle.crt";
            GIT_SSL_CAINFO = "/etc/ssl/certs/ca-bundle.crt";
          };
        };
      in
      {
        nixidy.applicationImports = [
          (generators.fromCRDModule {
            name = "renovate-operator";
            src = charts.mogenius.renovate-operator;
            crdFiles = [ "crd/renovate-operator.mogenius.com_renovatejobs.yaml" ];
            kindFilter = [ "RenovateJob" ];
          })
        ];

        applications.renovate = {
          inherit namespace;
          flux.dependsOn = [ "external-secrets-config" ];

          # The operator has no login configured, so it treats every request
          # as an admin's: Kanidm is the only gate.
          imports = [
            (cluster.methods.mkOidcAuth {
              name = "renovate";
              httpRouteName = "renovate";
              hostname = uiHost cluster;
              group = "admins";
            })
          ];

          helm.releases.renovate-operator = {
            chart = charts.mogenius.renovate-operator;
            values = {
              fullnameOverride = "renovate-operator";
              # The default, `hook`, installs the CRDs from a pre-install Job.
              crd.mode = "template";
              webhook = {
                enabled = true;
                baseUrl = "https://${webhookHost cluster}";
              };
              metrics = {
                enabled = true;
                serviceMonitor.enabled = true;
              };
              config = {
                defaultJobActiveDeadlineSeconds = 3600;
                jobTTLSecondsAfterFinished = 604800;
              };
              resources = {
                requests = {
                  cpu = "10m";
                  memory = "128Mi";
                };
                limits.memory = "512Mi";
              };
            };
          };

          resources.externalSecrets = {
            ${githubSecret}.spec = {
              secretStoreRef = {
                name = "onepassword";
                kind = "ClusterSecretStore";
              };
              target.name = githubSecret;
              data = [
                {
                  # The operator signs its JWT with the App's client ID as issuer.
                  secretKey = "client-id";
                  remoteRef.key = "${appItem}/credentials/client-id";
                }
                {
                  secretKey = "installation-id";
                  remoteRef.key = "${appItem}/credentials/installation-id";
                }
                {
                  secretKey = "private-key";
                  remoteRef = {
                    key = "${appItem}/credentials/private-key";
                    decodingStrategy = "Base64";
                  };
                }
              ];
            };
            ${webhookSecret}.spec = {
              secretStoreRef = {
                name = "onepassword";
                kind = "ClusterSecretStore";
              };
              target.name = webhookSecret;
              data = [
                {
                  secretKey = "token";
                  remoteRef.key = "${webhookItem}/credentials/token";
                }
              ];
            };
          };

          resources.renovateJobs.${jobName}.spec = {
            schedule = "0 */3 * * *";
            # A checkbox tick shouldn't wait behind other repositories' runs.
            parallelism = 3;
            provider.name = "github";
            discoveryFilters = [ "${githubOwner cluster}/*" ];
            image = images.renovate;
            githubAppReference = {
              secretName = githubSecret;
              appIdSecretKey = "client-id";
              installationIdSecretKey = "installation-id";
              pemSecretKey = "private-key";
            };
            metadata.labels."app.kubernetes.io/name" = "renovate";
            resources = {
              requests = {
                cpu = "250m";
                memory = "1Gi";
              };
              limits.memory = "8Gi";
            };
            webhook = {
              enabled = true;
              authentication = {
                enabled = true;
                secretRef = {
                  name = webhookSecret;
                  key = "token";
                };
              };
            };
            renovateConfig = {
              fileName = "config.json";
              inline = builtins.toJSON globalConfig;
            };
          };

          resources.httpRoutes = {
            renovate.spec = {
              parentRefs = [
                {
                  group = "gateway.networking.k8s.io";
                  kind = "Gateway";
                  name = "apps";
                  namespace = "envoy-gateway-system";
                  sectionName = "https";
                }
              ];
              hostnames = [ (uiHost cluster) ];
              rules = [
                {
                  backendRefs = [
                    {
                      name = "renovate-operator";
                      port = 8081;
                    }
                  ];
                }
              ];
            };

            renovate-webhook = {
              metadata.labels."home-ops.dev/public-dns" = "true";
              spec = {
                parentRefs = [
                  {
                    group = "gateway.networking.k8s.io";
                    kind = "Gateway";
                    name = "cloudflare-tunnel";
                    namespace = "cloudflare-tunnel-system";
                    sectionName = "http";
                  }
                ];
                hostnames = [ (webhookHost cluster) ];
                rules = [
                  {
                    # Only the GitHub and schedule endpoints are public.
                    matches = [
                      {
                        path = {
                          type = "Exact";
                          value = "/webhook/v1/github";
                        };
                      }
                      {
                        path = {
                          type = "Exact";
                          value = "/webhook/v1/schedule";
                        };
                      }
                    ];
                    backendRefs = [
                      {
                        group = "";
                        kind = "Service";
                        name = "renovate-operator";
                        port = 8082;
                        weight = 1;
                      }
                    ];
                  }
                ];
              };
            };
          };

          resources.ciliumNetworkPolicies = with cluster.methods.netpol; {
            renovate-operator = mkPolicy { app = "renovate-operator"; } {
              ingress = [
                (gatewayIngress 8081)
                (tunnelIngress 8082)
                (scrapeIngress [ 8080 ])
              ];
              egress = [
                apiserverEgress
                (worldEgress [ 443 ])
              ];
            };
            # Discovery and executor pods: GitHub, registries, the Nix caches.
            renovate = mkPolicy { "app.kubernetes.io/name" = "renovate"; } {
              egress = [ (worldEgress [ 443 ]) ];
            };
          };
        };
      };

    "terragrunt-stacks" =
      { cluster, ... }:
      {
        stack = "renovate-webhook";
        localModule = "renovate-webhook";
        inputs = {
          github_owner = githubOwner cluster;
          inherit repositories;
          push_schedules = pushSchedules;
          webhook_url = "https://${webhookHost cluster}/webhook/v1/github?namespace=${namespace}&job=${jobName}";
          schedule_url = "https://${webhookHost cluster}/webhook/v1/schedule?namespace=${namespace}&job=${jobName}";
          token_item = webhookItem;
        };
      };
  };
}
