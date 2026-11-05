# Sonarr, moving from pve1's CT 130. Renders at 0 replicas until its config
# is imported into the kopiur-backed volume.
_: {
  den.aspects.kubernetes.media.sonarr.k8s-manifests =
    { cluster, ... }:
    {
      applications.sonarr = cluster.methods.mkMediaApp {
        name = "sonarr";
        # renovate: datasource=docker depName=ghcr.io/home-operations/sonarr
        tag = "4.0.20.3012@sha256:1f19eb5e0f421418c1a956bbe01310a0141423afe28bd9a4b1dcb8629ff2bce2";
        port = 8989;
        # The CT's uid 351 behind the unprivileged-CT offset: what owns its
        # files on truenas. 100330 is sabnzbd's, which owns the downloads.
        uid = 100351;
        supplementalGroups = [ 100330 ];
        # The CT's own mount paths, which its database and sabnzbd's
        # reported paths refer to.
        nfs = {
          library = {
            path = "/mnt/tank/library/series";
            mountPath = "/tank/library/series";
          };
          downloads = {
            path = "/mnt/tank/downloads/sabnzbd";
            mountPath = "/var/lib/sabnzbd/Downloads";
          };
        };
        # Room for its database and cover art.
        storage = "2Gi";
        # Raised once the config is imported from pve1.
        replicas = 0;
      };
    };
}
