# Radarr, moving from pve1's CT 120. Renders at 0 replicas until its config
# is imported into the kopiur-backed volume.
_: {
  den.aspects.kubernetes.media.radarr.k8s-manifests =
    { cluster, ... }:
    {
      applications.radarr = cluster.methods.mkMediaApp {
        name = "radarr";
        # renovate: datasource=docker depName=ghcr.io/home-operations/radarr
        tag = "6.4.4.10685@sha256:1902ad2c08e9bac276ff9a1429af2eaa2f3c635a51f138f1b3eb734995171537";
        port = 7878;
        # The CT's uid 352 behind the unprivileged-CT offset: what owns its
        # files on truenas. 100330 is sabnzbd's, which owns the downloads.
        uid = 100352;
        supplementalGroups = [ 100330 ];
        # The CT's own mount paths, which its database and sabnzbd's
        # reported paths refer to.
        nfs = {
          library = {
            path = "/mnt/tank/library/movies";
            mountPath = "/tank/library/movies";
          };
          downloads = {
            path = "/mnt/tank/downloads/sabnzbd";
            mountPath = "/var/lib/sabnzbd/Downloads";
          };
        };
        # Room for its database and cover art.
        storage = "15Gi";
        # Raised once the config is imported from pve1.
        replicas = 0;
      };
    };
}
