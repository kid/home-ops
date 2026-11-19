# GitHub Actions runners for the cluster's own repository (`runs-on:
# home-ops`): actions-runner-controller's scale-set mode, one ephemeral
# runner pod per job, none while idle. The runner uses the node's Nix daemon
# (its socket, store and nix binary mounted from the host), so builds run in
# the host's sandbox and land in its store, which stays warm between jobs.
# The daemon runs fixed-output derivations in the host's network namespace,
# outside this namespace's policy: only same-repository pull requests may run
# here (the workflow's job condition), never forks.
_:
let
  controllerNamespace = "arc-system";
  controllerName = "arc";
  runnerNamespace = "arc-runners";
  scaleSetName = "home-ops";
  githubSecret = "arc-github-app";
  # 1Password item, in the cluster's vault (section `credentials`), holding
  # the GitHub App; the private key is base64, a PEM is multi-line.
  githubItem = "github-arc-app";

  # GitHub and the flake inputs, never the LAN.
  publicHttpsEgress = {
    toCIDRSet = [
      {
        cidr = "0.0.0.0/0";
        except = [
          "10.0.0.0/8"
          "172.16.0.0/12"
          "192.168.0.0/16"
          "100.64.0.0/10"
        ];
      }
    ];
    toPorts = [
      {
        ports = [
          {
            port = "443";
            protocol = "TCP";
          }
        ];
      }
    ];
  };
in
{
  den.aspects.kubernetes.actions-runner-controller.k8s-manifests =
    {
      charts,
      cluster,
      config,
      lib,
      ...
    }:
    {
      # The controller, and the listener pods it creates for each scale set.
      applications.actions-runner-controller = {
        namespace = controllerNamespace;

        resources.ciliumNetworkPolicies = with cluster.methods.netpol; {
          actions-runner-controller = mkPolicy { } {
            egress = [
              apiserverEgress
              publicHttpsEgress
            ];
          };
        };

        helm.releases.actions-runner-controller = {
          chart = charts.actions.gha-runner-scale-set-controller;
          values = {
            fullnameOverride = controllerName;
            flags = {
              logLevel = "info";
              logFormat = "json";
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
      };

      applications.actions-runners = {
        namespace = runnerNamespace;
        flux.dependsOn = [
          "external-secrets-config"
          "actions-runner-controller"
        ];

        resources.ciliumNetworkPolicies = with cluster.methods.netpol; {
          actions-runners = mkPolicy { } {
            egress = [ publicHttpsEgress ];
          };
        };

        resources.externalSecrets.${githubSecret}.spec = {
          secretStoreRef = {
            name = "onepassword";
            kind = "ClusterSecretStore";
          };
          target.name = githubSecret;
          data = [
            {
              # ARC takes the App's client ID here too.
              secretKey = "github_app_id";
              remoteRef.key = "${githubItem}/credentials/client-id";
            }
            {
              secretKey = "github_app_installation_id";
              remoteRef.key = "${githubItem}/credentials/installation-id";
            }
            {
              secretKey = "github_app_private_key";
              remoteRef = {
                key = "${githubItem}/credentials/private-key";
                decodingStrategy = "Base64";
              };
            }
          ];
        };

        helm.releases.actions-runners = {
          chart = charts.actions.gha-runner-scale-set;
          values = {
            githubConfigUrl = cluster.nixidy.repository |> builtins.match "(.*)\\.git" |> builtins.head;
            githubConfigSecret = githubSecret;
            runnerScaleSetName = scaleSetName;
            minRunners = 0;
            # Every job builds on the same node's daemon.
            maxRunners = 1;
            # The chart would look the controller up in the live cluster.
            controllerServiceAccount = {
              namespace = controllerNamespace;
              name = controllerName;
            };
            template.spec = {
              containers = [
                {
                  name = "runner";
                  # renovate: datasource=docker depName=ghcr.io/actions/actions-runner
                  image = "ghcr.io/actions/actions-runner:2.338.2@sha256:6d0b2d80d80f143f77dcb676e50920100bbb547e39e883454d57f45ab8c31300";
                  command = [ "/home/runner/run.sh" ];
                  env = [
                    {
                      name = "PATH";
                      value = "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/run/current-system/sw/bin";
                    }
                    {
                      name = "NIX_REMOTE";
                      value = "daemon";
                    }
                    {
                      # The image has no nix.conf; the daemon's settings stay the host's.
                      name = "NIX_CONFIG";
                      value = "experimental-features = nix-command flakes pipe-operators";
                    }
                  ];
                  resources = {
                    requests = {
                      cpu = "500m";
                      memory = "1Gi";
                    };
                    # Evaluation only: the builds run in the daemon's cgroup.
                    limits.memory = "8Gi";
                  };
                  volumeMounts = [
                    {
                      name = "nix-store";
                      mountPath = "/nix/store";
                      readOnly = true;
                    }
                    {
                      name = "nix-daemon-socket";
                      mountPath = "/nix/var/nix/daemon-socket";
                    }
                    {
                      name = "current-system";
                      mountPath = "/run/current-system";
                      readOnly = true;
                    }
                  ];
                }
              ];
              volumes = [
                {
                  name = "nix-store";
                  hostPath = {
                    path = "/nix/store";
                    type = "Directory";
                  };
                }
                {
                  name = "nix-daemon-socket";
                  hostPath = {
                    path = "/nix/var/nix/daemon-socket";
                    type = "Directory";
                  };
                }
                {
                  name = "current-system";
                  hostPath = {
                    path = "/run/current-system";
                    type = "Directory";
                  };
                }
              ];
            };
          };

          # The controller deletes a runner set whose app.kubernetes.io/version
          # isn't its own, so that label survives the default transformer.
          transformer =
            manifests:
            let
              version =
                (lib.findFirst (m: m.kind == "AutoscalingRunnerSet") null manifests)
                .metadata.labels."app.kubernetes.io/version";
            in
            config.nixidy.defaults.helm.transformer manifests
            |> map (
              m:
              if m.kind == "AutoscalingRunnerSet" then
                lib.recursiveUpdate m { metadata.labels."app.kubernetes.io/version" = version; }
              else
                m
            );
        };
      };
    };
}
