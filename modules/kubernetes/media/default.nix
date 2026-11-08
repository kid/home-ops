# The shape every media app here shares: one Deployment on a kopiur-backed
# config volume, its Service and HTTPRoute on the apps Gateway, NFS mounts
# from node0's tank pool, and its Cilium policy. Returns the nixidy application, for
# `applications.<name>`.
{ config, lib, ... }:
let
  inherit (config.den.clusters.prd) methods;

  # The nodes reach node0 on the Storage VLAN, not through the router.
  nfsServer =
    config.den.devices.node0.interfaces
    |> lib.findFirst (i: i.network == "Storage") (throw "node0 has no Storage interface")
    |> (i: i.address);

  mkMediaApp =
    {
      name,
      # The image's app: animarr is a second sonarr.
      app ? name,
      # The *arr family (Sonarr, Radarr, Prowlarr), configured through the
      # same env and probed on /ping.
      servarr ? true,
      env ? { },
      probePath ? "/ping",
      tag,
      port,
      # Also the kopiur mover's uid, and the owner of what it writes over NFS.
      uid,
      supplementalGroups ? [ ],
      # <volume> = { path = <export on node0>; mountPath = <in the pod>;
      # readOnly ? false; }
      nfs ? { },
      storage ? "1Gi",
      # null leaves it to the HPA from mkNfsScaler.
      replicas ? null,
      # Out to the world (indexers, metadata, Usenet servers).
      egressPorts ? [
        80
        443
      ],
      memoryLimit ? "1Gi",
      # More paths the app rebuilds, kept out of the snapshots.
      backupIgnore ? [ ],
      # The HTTPRoute's request timeout; Envoy's own default is 15s.
      requestTimeout ? null,
      # The env var the app reads its API key from; null for none. The key is
      # generated once into the <name>-api-key Secret, which the other apps
      # read too.
      apiKeyEnv ? if servarr then "${lib.toUpper app}__AUTH__APIKEY" else null,
    }:
    let
      labels."app.kubernetes.io/name" = name;
      namespace = "media";
      hostname = methods.mkAppHostname name;
      # What the media apps call each other by.
      serviceHostname = "${name}.${namespace}.svc.cluster.local";
      envPrefix = lib.toUpper app;
      # Host filtering always admits localhost, but not the pod IP the
      # kubelet would send.
      probe = {
        path = probePath;
        port = "http";
        httpHeaders = [
          {
            name = "Host";
            value = "localhost";
          }
        ];
      };
      apiKeySecret = "${name}-api-key";
    in
    {
      inherit namespace;
      flux.dependsOn = [
        # The kopiur webhook admits the backup objects.
        "kopiur-config"
      ]
      # The API key's Password generator and ExternalSecret.
      ++ lib.optional (apiKeyEnv != null) "external-secrets-config";

      resources =
        methods.mkKopiurBackup {
          inherit name uid storage;
          # Cover art and indexer definitions are re-downloaded, the rest is
          # the app's own logs and zip backups.
          ignore = [
            "/MediaCover"
            "/Definitions"
            "/Backups"
            "/Sentry"
            "/UpdateLogs"
            "/logs"
            "/logs.db*"
          ]
          ++ backupIgnore;
        }
        // lib.optionalAttrs (replicas == null) (methods.mkNfsScaler { inherit name; })
        // lib.optionalAttrs (apiKeyEnv != null) {
          # Generated once: the other apps keep it in their own settings.
          passwords.${apiKeySecret}.spec = {
            length = 32;
            digits = 10;
            symbols = 0;
            noUpper = true;
            allowRepeat = true;
            secretKeys = [ "api-key" ];
          };
          externalSecrets.${apiKeySecret}.spec = {
            refreshPolicy = "CreatedOnce";
            target.name = apiKeySecret;
            dataFrom = [
              {
                sourceRef.generatorRef = {
                  apiVersion = "generators.external-secrets.io/v1alpha1";
                  kind = "Password";
                  name = apiKeySecret;
                };
              }
            ];
          };
        }
        // {
          ciliumNetworkPolicies.${name} =
            with methods.netpol;
            mkPolicy labels {
              ingress = [
                (gatewayIngress port)
                # The other media apps, by Service name.
                (fromPods { } [ port ])
              ];
              # Indexers and metadata (world); the other media apps, by
              # Service name.
              egress = [
                (worldEgress egressPorts)
                { toEndpoints = [ { } ]; }
              ];
            };

          deployments.${name}.spec = lib.optionalAttrs (replicas != null) { inherit replicas; } // {
            strategy.type = "Recreate";
            selector.matchLabels = labels;
            template = {
              metadata = { inherit labels; };
              spec = {
                automountServiceAccountToken = false;
                securityContext = {
                  runAsNonRoot = true;
                  runAsUser = uid;
                  runAsGroup = uid;
                  fsGroup = uid;
                  fsGroupChangePolicy = "OnRootMismatch";
                  seccompProfile.type = "RuntimeDefault";
                }
                // lib.optionalAttrs (supplementalGroups != [ ]) { inherit supplementalGroups; };
                containers.${name} = {
                  image = "ghcr.io/home-operations/${app}:${tag}";
                  env =
                    lib.mapAttrs (_: value: { inherit value; }) (
                      lib.optionalAttrs servarr {
                        # No login of its own; Kanidm in front of it comes later.
                        "${envPrefix}__AUTH__METHOD" = "External";
                        "${envPrefix}__AUTH__REQUIRED" = "DisabledForLocalAddresses";
                        # Only requests through the apps Gateway or the Service.
                        "${envPrefix}__SERVER__ALLOWEDHOSTS" = "${hostname},${serviceHostname}";
                        # Logs go to stdout; the log database behind System ->
                        # Events only duplicates them.
                        "${envPrefix}__LOG__DBENABLED" = "false";
                        # Over whatever level the imported config.xml carries.
                        "${envPrefix}__LOG__LEVEL" = "info";
                      }
                      // env
                    )
                    // lib.optionalAttrs (apiKeyEnv != null) {
                      ${apiKeyEnv}.valueFrom.secretKeyRef = {
                        name = apiKeySecret;
                        key = "api-key";
                      };
                    };
                  ports.http.containerPort = port;
                  # Database migrations run before the app answers.
                  startupProbe = {
                    httpGet = probe;
                    failureThreshold = 60;
                  };
                  livenessProbe.httpGet = probe;
                  readinessProbe.httpGet = probe;
                  securityContext = {
                    allowPrivilegeEscalation = false;
                    readOnlyRootFilesystem = true;
                    capabilities.drop = [ "ALL" ];
                  };
                  resources = {
                    requests = {
                      cpu = "50m";
                      memory = "256Mi";
                    };
                    limits.memory = memoryLimit;
                  };
                  volumeMounts = {
                    "/config".name = "config";
                    # The log files have no off switch; keep them off the
                    # volume.
                    "/config/logs".name = "logs";
                    "/tmp".name = "tmp";
                  }
                  // lib.mapAttrs' (
                    volume: v:
                    lib.nameValuePair v.mountPath (
                      { name = volume; } // lib.optionalAttrs (v.readOnly or false) { readOnly = true; }
                    )
                  ) nfs;
                };
                volumes = {
                  config.persistentVolumeClaim.claimName = name;
                  logs.emptyDir = { };
                  tmp.emptyDir = { };
                }
                // lib.mapAttrs (_: v: {
                  nfs = {
                    server = nfsServer;
                    inherit (v) path;
                  }
                  // lib.optionalAttrs (v.readOnly or false) { readOnly = true; };
                }) nfs;
              };
            };
          };

          services.${name}.spec = {
            selector = labels;
            ports.http = {
              inherit port;
              targetPort = "http";
            };
          };

          httpRoutes.${name}.spec = {
            parentRefs = [
              {
                group = "gateway.networking.k8s.io";
                kind = "Gateway";
                name = "apps";
                namespace = "envoy-gateway-system";
                sectionName = "https";
              }
            ];
            hostnames = [ hostname ];
            rules = [
              (
                {
                  backendRefs = [ { inherit name port; } ];
                }
                // lib.optionalAttrs (requestTimeout != null) { timeouts.request = requestTimeout; }
              )
            ];
          };
        };
    };
in
{
  den.clusters.prd.methods.mkMediaApp = mkMediaApp;
  den.clusters.prd.methods.mediaNfsServer = nfsServer;
}
