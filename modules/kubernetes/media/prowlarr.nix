# Prowlarr, the indexer manager the *arr apps search through, moved from
# pve1's CT 110. Its config is imported once into the kopiur-backed volume,
# with replicas at 0 until then so it never starts on an empty one.
{ config, lib, ... }:
let
  name = "prowlarr";
  port = 9696;
  # The image runs as any uid; the kopiur mover reads the volume as this one.
  appId = 1000;
  # renovate: datasource=docker depName=ghcr.io/home-operations/prowlarr
  tag = "3.0.0.5737@sha256:0954599432e16ccd86129f1eb8eb0247fd0d1591aab400f73e2010a1cda37be8";
  labels."app.kubernetes.io/name" = name;

  # Still on pve1 behind their own Caddy: Prowlarr syncs its indexers into
  # them and sends grabs to sabnzbd, and they call it back through the apps
  # Gateway. Drop each one as it moves into the cluster.
  pve1Apps = {
    radarr = "10.0.30.120";
    sonarr = "10.0.30.130";
    animarr = "10.0.30.140";
    sabnzbd = "10.0.30.150";
  };
in
{
  den.aspects.kubernetes.media.prowlarr.firewall =
    { cluster, ... }:
    [
      {
        inherit (cluster) network;
        forward =
          pve1Apps
          |> lib.mapAttrsToList (
            app: address: {
              action = "accept";
              dst_address = address;
              dst_port = 443;
              protocol = "tcp";
              comment = "Allow prowlarr in K3s to reach ${app} on pve1";
            }
          );
      }
      {
        network = config.den.networks.Media.name;
        forward = [
          {
            action = "accept";
            dst_address = cluster.networks.loadBalancer.cidr;
            dst_port = 443;
            protocol = "tcp";
            comment = "Allow the *arr apps on pve1 to reach prowlarr in K3s";
          }
        ];
      }
    ];

  den.aspects.kubernetes.media.prowlarr.k8s-manifests =
    { cluster, ... }:
    {
      applications.prowlarr = {
        namespace = "media";
        # The kopiur webhook admits the backup objects.
        flux.dependsOn = [ "kopiur-config" ];

        resources =
          cluster.methods.mkKopiurBackup {
            inherit name;
            uid = appId;
          }
          // {
            ciliumNetworkPolicies.${name} =
              with cluster.methods.netpol;
              mkPolicy labels {
                ingress = [ (gatewayIngress port) ];
                # Indexers, and the apps on pve1.
                egress = [
                  (worldEgress [
                    80
                    443
                  ])
                ];
              };

            deployments.${name}.spec = {
              # Raised once the config is imported from pve1.
              replicas = 0;
              strategy.type = "Recreate";
              selector.matchLabels = labels;
              template = {
                metadata = { inherit labels; };
                spec = {
                  automountServiceAccountToken = false;
                  securityContext = {
                    runAsNonRoot = true;
                    runAsUser = appId;
                    runAsGroup = appId;
                    fsGroup = appId;
                    fsGroupChangePolicy = "OnRootMismatch";
                    seccompProfile.type = "RuntimeDefault";
                  };
                  containers.${name} = {
                    image = "ghcr.io/home-operations/prowlarr:${tag}";
                    env = lib.mapAttrs (_: value: { inherit value; }) {
                      # No login of its own; Kanidm in front of it comes later.
                      PROWLARR__AUTH__METHOD = "External";
                      PROWLARR__AUTH__REQUIRED = "DisabledForLocalAddresses";
                    };
                    ports.http.containerPort = port;
                    # Database migrations run before /ping answers.
                    startupProbe.httpGet = {
                      path = "/ping";
                      port = "http";
                    };
                    startupProbe.failureThreshold = 60;
                    livenessProbe.httpGet = {
                      path = "/ping";
                      port = "http";
                    };
                    readinessProbe.httpGet = {
                      path = "/ping";
                      port = "http";
                    };
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
                      "/tmp".name = "tmp";
                    };
                  };
                  volumes = {
                    config.persistentVolumeClaim.claimName = name;
                    tmp.emptyDir = { };
                  };
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
              hostnames = [ (cluster.methods.mkAppHostname name) ];
              rules = [ { backendRefs = [ { inherit name port; } ]; } ];
            };
          };
      };
    };
}
