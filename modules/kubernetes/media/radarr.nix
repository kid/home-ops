# Radarr, moved from pve1's CT 120, whose config was imported once into the
# kopiur-backed volume.
_: {
  den.aspects.kubernetes.media.radarr.k8s-manifests =
    { cluster, ... }:
    {
      applications.radarr = cluster.methods.mkMediaApp {
        name = "radarr";
        # renovate: datasource=docker depName=ghcr.io/home-operations/radarr
        tag = "7.0.2.10888@sha256:69ea515df6e2a3ea1490cfa127ffaaf9597a9db84fffa2fa150a6fae98fe04cb";
        port = 7878;
        # The CT's uid 352 behind the unprivileged-CT offset: what owns its
        # files on tank. 100330 is sabnzbd's, which owns the downloads.
        uid = 100352;
        supplementalGroups = [ 100330 ];
        # The CT's own mount paths, which its database and sabnzbd's
        # reported paths refer to.
        nfs = {
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
      };
    };
}
