# Unpackerr: extracts archives SABnzbd left packed in a completed download,
# so the *arr app it belongs to can import it. It works from their queues,
# through their APIs.
{ lib, ... }:
let
  name = "unpackerr";
  labels."app.kubernetes.io/name" = name;
  # SABnzbd's uid, which owns the downloads; the *arr apps share its group.
  uid = 100330;
  downloads = "/var/lib/sabnzbd/Downloads";
  # renovate: datasource=docker depName=ghcr.io/unpackerr/unpackerr
  tag = "v1.0.1@sha256:22b4693fbeaae4bd927905d63b59b8f67b4a1446682d965ac876c61a48976658";

  # <UN_ app prefix> = { instance; port; }
  apps = {
    SONARR_0 = {
      instance = "sonarr";
      port = 8989;
    };
    SONARR_1 = {
      instance = "animarr";
      port = 8989;
    };
    RADARR_0 = {
      instance = "radarr";
      port = 7878;
    };
  };
in
{
  den.aspects.kubernetes.media.unpackerr.k8s-manifests =
    { cluster, ... }:
    {
      applications.unpackerr = {
        namespace = "media";
        # The apps create the <instance>-api-key Secrets it reads.
        flux.dependsOn = apps |> lib.mapAttrsToList (_: a: a.instance);

        resources = cluster.methods.mkNfsScaler { inherit name; } // {

          ciliumNetworkPolicies.${name} =
            with cluster.methods.netpol;
            mkPolicy labels {
              egress = [
                (toPods { } (apps |> lib.mapAttrsToList (_: a: a.port) |> lib.unique))
              ];
            };

          deployments.${name}.spec = {
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
                  seccompProfile.type = "RuntimeDefault";
                };
                containers.${name} = {
                  image = "ghcr.io/unpackerr/unpackerr:${tag}";
                  env =
                    lib.mapAttrs (_: value: { inherit value; }) (
                      {
                        # Group-writable, like SABnzbd's own output, so the
                        # *arr apps can move and delete what it extracts.
                        UN_FILE_MODE = "0664";
                        UN_DIR_MODE = "0775";
                      }
                      // lib.concatMapAttrs (prefix: a: {
                        "UN_${prefix}_NAME" = a.instance;
                        "UN_${prefix}_URL" = "http://${a.instance}.media.svc.cluster.local:${toString a.port}";
                        "UN_${prefix}_PATHS_0" = downloads;
                        # torrent only by default.
                        "UN_${prefix}_PROTOCOLS" = "usenet,UsenetDownloadProtocol";
                      }) apps
                    )
                    // lib.mapAttrs' (
                      prefix: a:
                      lib.nameValuePair "UN_${prefix}_API_KEY" {
                        valueFrom.secretKeyRef = {
                          name = "${a.instance}-api-key";
                          key = "api-key";
                        };
                      }
                    ) apps;
                  securityContext = {
                    allowPrivilegeEscalation = false;
                    readOnlyRootFilesystem = true;
                    capabilities.drop = [ "ALL" ];
                  };
                  resources = {
                    requests = {
                      cpu = "10m";
                      memory = "64Mi";
                    };
                    limits.memory = "512Mi";
                  };
                  volumeMounts = {
                    ${downloads}.name = "downloads";
                    "/tmp".name = "tmp";
                  };
                };
                volumes = {
                  downloads.nfs = {
                    server = cluster.methods.mediaNfsServer;
                    path = "/mnt/tank/downloads/sabnzbd";
                  };
                  tmp.emptyDir = { };
                };
              };
            };
          };
        };
      };
    };
}
