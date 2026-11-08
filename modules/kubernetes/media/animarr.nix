# animarr, the Sonarr instance for anime, moved from pve1's CT 140, whose
# config was imported once into the kopiur-backed volume.
_: {
  den.aspects.kubernetes.media.animarr.k8s-manifests =
    { cluster, ... }:
    {
      applications.animarr = cluster.methods.mkMediaApp {
        name = "animarr";
        app = "sonarr";
        # renovate: datasource=docker depName=ghcr.io/home-operations/sonarr
        tag = "4.0.20.3012@sha256:1f19eb5e0f421418c1a956bbe01310a0141423afe28bd9a4b1dcb8629ff2bce2";
        port = 8989;
        # The CT's uid 350 behind the unprivileged-CT offset: what owns its
        # files on tank. 100330 is sabnzbd's, which owns the downloads.
        uid = 100350;
        supplementalGroups = [ 100330 ];
        # The CT's own mount paths, which its database and sabnzbd's
        # reported paths refer to.
        nfs = {
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
    };
}
