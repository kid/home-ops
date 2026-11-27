# animarr, the Sonarr instance for anime, moved from pve1's CT 140, whose
# config was imported once into the kopiur-backed volume.
_: {
  den.aspects.kubernetes.media.animarr.generated-secrets = { cluster, ... }: [
    (cluster.methods.mkMediaApiKey "animarr")
  ];

  den.aspects.kubernetes.media.animarr.k8s-manifests =
    { cluster, ... }:
    cluster.methods.mkMediaApp {
      name = "animarr";
      app = "sonarr";
      # renovate: datasource=docker depName=ghcr.io/home-operations/sonarr
      tag = "5.0.0.3041@sha256:ec7797f30e65cc411fba6768ed575337a5787de7d06c382173df610f2d23a317";
      port = 8989;
      # The CT's uid 350 behind the unprivileged-CT offset: what owns its
      # files on tank. 100330 is sabnzbd's, which owns the downloads.
      uid = 100350;
      supplementalGroups = [ 100330 ];
      # The CT's own mount paths, which its database and sabnzbd's
      # reported paths refer to.
      hostPaths = {
        library = {
          path = "/tank/library/animes";
          mountPath = "/tank/library/animes";
        };
        downloads = {
          path = "/tank/downloads/sabnzbd";
          mountPath = "/var/lib/sabnzbd/Downloads";
        };
      };
    };
}
