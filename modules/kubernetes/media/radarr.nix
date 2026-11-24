# Radarr, moved from pve1's CT 120, whose config was imported once into the
# kopiur-backed volume.
_: {
  den.aspects.kubernetes.media.radarr.generated-secrets = { cluster, ... }: [
    (cluster.methods.mkMediaApiKey "radarr")
  ];

  den.aspects.kubernetes.media.radarr.k8s-manifests =
    { cluster, ... }:
    cluster.methods.mkMediaApp {
      name = "radarr";
      # renovate: datasource=docker depName=ghcr.io/home-operations/radarr
      tag = "7.1.0.10948@sha256:d259bde2be6b1997c1832cf981d50017f919b305ed3dc9ce445c4661956553f3";
      port = 7878;
      # The CT's uid 352 behind the unprivileged-CT offset: what owns its
      # files on tank. 100330 is sabnzbd's, which owns the downloads.
      uid = 100352;
      supplementalGroups = [ 100330 ];
      # The CT's own mount paths, which its database and sabnzbd's
      # reported paths refer to.
      hostPaths = {
        library = {
          path = "/tank/library/movies";
          mountPath = "/tank/library/movies";
        };
        downloads = {
          path = "/tank/downloads/sabnzbd";
          mountPath = "/var/lib/sabnzbd/Downloads";
        };
      };
      # Room for its database and cover art.
      storage = "15Gi";
      memoryRequest = "768Mi";
    };
}
