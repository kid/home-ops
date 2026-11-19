# Recyclarr: syncs the TRaSH Guides' quality profiles, custom formats and
# quality sizes into Radarr, Sonarr and animarr every night. It adopts
# custom formats that already exist by name; profiles it creates under the
# guide's names, and tracks both by id in its state after that.
{ lib, ... }:
let
  name = "recyclarr";
  labels."app.kubernetes.io/name" = name;
  # The image's own user, which owns /config.
  uid = 1000;
  # renovate: datasource=docker depName=ghcr.io/recyclarr/recyclarr
  tag = "8.8.1@sha256:3e9c41b9ec29bbf65fe846864058730d321a21f7695d8c0d9437b73e34d50ad9";

  # Each instance's API key, from the <instance>-api-key Secret.
  apiKeyEnv = instance: "${lib.toUpper instance}_API_KEY";
  instance = instance: port: {
    base_url = "http://${instance}.media.svc.cluster.local:${toString port}";
    # Swapped for the !env_var tag below: the YAML generator can't write tags.
    api_key = apiKeyEnv instance;
    # Only the ones it synced itself, once dropped from the guide or here.
    delete_old_custom_formats = true;
  };
  # Every playback direct-plays, so DV without an HDR10 fallback (Profile 5)
  # stays allowed: the "DV (w/o HDR fallback)" group is left out.
  profile = trashId: {
    trash_id = trashId;
    # Zero the scores of custom formats it doesn't manage.
    reset_unmatched_scores.enabled = true;
  };

  recyclarrConfig = {
    radarr.radarr = instance "radarr" 7878 // {
      quality_definition.type = "movie";
      # Remux 2160p (Combined)
      quality_profiles = [ (profile "d1d310673359205736b4b84acd5ea8c8") ];
      # Audio Formats (Atmos first), HDR and Unwanted Formats (BR-DISK) are
      # on by default.
      custom_format_groups.add = [
        # [HDR Formats] DV Boost
        { trash_id = "1616617ab3a14397a2b2321bcbda44d1"; }
        # [HDR Formats] HDR10+ Boost
        { trash_id = "b29413a7487478fe98228ce79e5689e4"; }
        {
          # [Optional] Miscellaneous
          trash_id = "9337080378236ce4c0b183e35790d2a7";
          # DV (Disk): the disc's own DV layer (Profile 7) over WEB hybrids.
          select = [ "f700d29429c023a5734505e77daeaea7" ];
        }
      ];
    };
    sonarr = {
      sonarr = instance "sonarr" 8989 // {
        quality_definition.type = "series";
        # Remux 2160p (Combined)
        quality_profiles = [ (profile "911df0e05a395c19d8b3efc76a7467c1") ];
        custom_format_groups.add = [
          # [Audio] Audio Formats: not a default for Sonarr.
          { trash_id = "e9a1944a254e6f8a9da63083f7ae15cb"; }
          # [HDR Formats] DV Boost
          { trash_id = "e0b2774083df4265f25c9e5bc6c80940"; }
          # [HDR Formats] HDR10+ Boost
          { trash_id = "7d366c213e5c23a052b157356fac1921"; }
          {
            # [Optional] Miscellaneous
            trash_id = "f4a0410a1df109a66d6e47dcadcce014";
            # DV (Disk)
            select = [ "ef4963043b0987f8485bc9106f16db38" ];
          }
        ];
      };
      animarr = instance "animarr" 8989 // {
        quality_definition.type = "anime";
        # [Anime] Remux-1080p
        quality_profiles = [ (profile "20e0fc959f1f1704bed501f23bdae76f") ];
      };
    };
  };
  instances = recyclarrConfig.radarr // recyclarrConfig.sonarr |> lib.attrNames;
in
{
  den.aspects.kubernetes.media.recyclarr.k8s-manifests =
    { cluster, pkgs, ... }:
    {
      applications.recyclarr = {
        namespace = "media";
        # The apps create the <instance>-api-key Secrets it reads.
        flux.dependsOn = instances;

        resources = {
          configMaps.${name}.data."recyclarr.yml" =
            (pkgs.formats.yaml { }).generate "recyclarr.yml" recyclarrConfig
            |> builtins.readFile
            |> lib.replaceStrings (map (i: "api_key: ${apiKeyEnv i}") instances) (
              map (i: "api_key: !env_var ${apiKeyEnv i}") instances
            );

          # Its state (what it synced, by id), which delete_old_custom_formats
          # needs, and the guides' clone. Pending, and its Kustomization
          # unready, until the first Job binds it.
          persistentVolumeClaims.${name}.spec = {
            storageClassName = cluster.storage.replicatedClass;
            accessModes = [ "ReadWriteOncePod" ];
            resources.requests.storage = "1Gi";
          };

          ciliumNetworkPolicies.${name} =
            with cluster.methods.netpol;
            mkPolicy labels {
              egress = [
                (toPods { } [
                  7878
                  8989
                ])
                # The TRaSH Guides and config templates repositories.
                (fqdnEgress [ "github.com" ] [ 443 ])
              ];
            };

          cronJobs.${name}.spec = {
            schedule = "0 5 * * *";
            concurrencyPolicy = "Forbid";
            jobTemplate.spec = {
              # A failed sync waits for the next night, and KubeJobFailed.
              backoffLimit = 0;
              template = {
                metadata = { inherit labels; };
                spec = {
                  restartPolicy = "Never";
                  automountServiceAccountToken = false;
                  securityContext = {
                    runAsNonRoot = true;
                    runAsUser = uid;
                    runAsGroup = uid;
                    fsGroup = uid;
                    fsGroupChangePolicy = "OnRootMismatch";
                    seccompProfile.type = "RuntimeDefault";
                  };
                  containers.${name} = {
                    image = "ghcr.io/recyclarr/recyclarr:${tag}";
                    # The entrypoint runs the CLI when given arguments.
                    args = [ "sync" ];
                    env =
                      instances
                      |> map (
                        i:
                        lib.nameValuePair (apiKeyEnv i) {
                          valueFrom.secretKeyRef = {
                            name = "${i}-api-key";
                            key = "api-key";
                          };
                        }
                      )
                      |> lib.listToAttrs;
                    securityContext = {
                      allowPrivilegeEscalation = false;
                      readOnlyRootFilesystem = true;
                      capabilities.drop = [ "ALL" ];
                    };
                    resources = {
                      requests = {
                        cpu = "50m";
                        memory = "128Mi";
                      };
                      limits.memory = "512Mi";
                    };
                    volumeMounts = {
                      "/config".name = "config";
                      # Recyclarr reads every configs/*.yml.
                      "/config/configs".name = "configs";
                      "/tmp".name = "tmp";
                    };
                  };
                  volumes = {
                    config.persistentVolumeClaim.claimName = name;
                    configs.configMap.name = name;
                    tmp.emptyDir = { };
                  };
                };
              };
            };
          };
        };
      };
    };
}
