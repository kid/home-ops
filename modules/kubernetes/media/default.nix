# The shape every *arr app here shares: one Deployment on a kopiur-backed
# config volume, its Service and HTTPRoute on the apps Gateway, NFS mounts
# from truenas, and its Cilium policy. Returns the nixidy application, for
# `applications.<name>`.
{ config, lib, ... }:
let
  inherit (config.den.clusters.prd) methods;

  # The nodes reach truenas on the Storage VLAN, not through the router.
  nfsServer =
    config.den.devices.truenas.interfaces
    |> lib.findFirst (i: i.network == "Storage") (throw "truenas has no Storage interface")
    |> (i: i.address);

  mkMediaApp =
    {
      name,
      # The servarr app the image runs: animarr is a second sonarr.
      app ? name,
      tag,
      port,
      # Also the kopiur mover's uid, and the owner of what it writes over NFS.
      uid,
      supplementalGroups ? [ ],
      # <volume> = { path = <export on truenas>; mountPath = <in the pod>; }
      nfs ? { },
      storage ? "1Gi",
      # null leaves it to the HPA from mkNfsScaler.
      replicas ? null,
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
      ping = {
        path = "/ping";
        port = "http";
        httpHeaders = [
          {
            name = "Host";
            value = "localhost";
          }
        ];
      };
    in
    {
      inherit namespace;
      # The kopiur webhook admits the backup objects.
      flux.dependsOn = [ "kopiur-config" ];

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
          ];
        }
        // lib.optionalAttrs (replicas == null) (methods.mkNfsScaler { inherit name; })
        // {
          ciliumNetworkPolicies.${name} =
            with methods.netpol;
            mkPolicy labels {
              ingress = [
                (gatewayIngress port)
                # The other media apps, by Service name.
                (fromPods { } [ port ])
              ];
              # Indexers, metadata and the apps still on pve1 (world); the
              # other media apps, by Service name.
              egress = [
                (worldEgress [
                  80
                  443
                ])
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
                  env = lib.mapAttrs (_: value: { inherit value; }) {
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
                  };
                  ports.http.containerPort = port;
                  # Database migrations run before /ping answers.
                  startupProbe = {
                    httpGet = ping;
                    failureThreshold = 60;
                  };
                  livenessProbe.httpGet = ping;
                  readinessProbe.httpGet = ping;
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
                    limits.memory = "1Gi";
                  };
                  volumeMounts = {
                    "/config".name = "config";
                    # The log files have no off switch; keep them off the
                    # volume.
                    "/config/logs".name = "logs";
                    "/tmp".name = "tmp";
                  }
                  // lib.mapAttrs' (volume: v: lib.nameValuePair v.mountPath { name = volume; }) nfs;
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
                  };
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
            rules = [ { backendRefs = [ { inherit name port; } ]; } ];
          };
        };
    };
in
{
  den.clusters.prd.methods.mkMediaApp = mkMediaApp;
}
