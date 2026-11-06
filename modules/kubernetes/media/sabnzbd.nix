# SABnzbd, the Usenet downloader the *arr apps send grabs to, moving from
# pve1's CT 150. Renders at 0 replicas until its config is imported into the
# kopiur-backed volume.
_: {
  den.aspects.kubernetes.media.sabnzbd.k8s-manifests =
    { cluster, ... }:
    {
      applications.sabnzbd = cluster.methods.mkMediaApp {
        name = "sabnzbd";
        servarr = false;
        # renovate: datasource=docker depName=ghcr.io/home-operations/sabnzbd
        tag = "5.1.3@sha256:c89b0322721c3eba47221e5f916505e7e742684651f73c5215717340b6b5402f";
        port = 8080;
        # The image writes these into sabnzbd.ini at start, after the pod's
        # own hostname.
        env.SABNZBD__HOST_WHITELIST_ENTRIES = "sabnzbd.kidibox.net, sabnzbd.media.svc.cluster.local";
        probePath = "/api?mode=version";
        # The CT's uid 330 behind the unprivileged-CT offset: what owns the
        # downloads on truenas.
        uid = 100330;
        # The CT's own mount path, which sabnzbd.ini and the *arr apps'
        # completed-download paths refer to.
        nfs.downloads = {
          path = "/mnt/tank/downloads/sabnzbd";
          mountPath = "/var/lib/sabnzbd/Downloads";
        };
        # NNTP over TLS to the Usenet servers.
        egressPorts = [
          80
          443
          563
        ];
        # Its 1G article cache, plus par2 repair and unpacking.
        memoryLimit = "3Gi";
        # Raised once the config is imported from pve1.
        replicas = 0;
      };
    };
}
