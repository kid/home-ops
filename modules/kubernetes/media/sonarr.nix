# Sonarr, moved from pve1's CT 130, whose config was imported once into the
# kopiur-backed volume.
_: {
  den.aspects.kubernetes.media.sonarr.k8s-manifests =
    { cluster, ... }:
    {
      applications.sonarr = cluster.methods.mkMediaApp {
        name = "sonarr";
        # renovate: datasource=docker depName=ghcr.io/home-operations/sonarr
        tag = "5.0.0.2941@sha256:93b0923dd12afd43247739e19dac59d74c52a15ea12e036b7ced264cffb42574";
        port = 8989;
        # The CT's uid 351 behind the unprivileged-CT offset: what owns its
        # files on tank. 100330 is sabnzbd's, which owns the downloads.
        uid = 100351;
        supplementalGroups = [ 100330 ];
        # The CT's own mount paths, which its database and sabnzbd's
        # reported paths refer to.
        nfs = {
          library = {
            path = "/tank/library/series";
            mountPath = "/tank/library/series";
          };
          downloads = {
            path = "/tank/downloads/sabnzbd";
            mountPath = "/var/lib/sabnzbd/Downloads";
          };
        };
        # Room for its database and cover art.
        storage = "2Gi";
      };
    };
}
