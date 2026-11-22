# SABnzbd, the Usenet downloader the *arr apps send grabs to, moved from
# pve1's CT 150, whose config was imported once into the kopiur-backed
# volume.
_: {
  den.aspects.kubernetes.media.sabnzbd.generated-secrets = { cluster, ... }: [
    (cluster.methods.mkMediaApiKey "sabnzbd")
  ];

  den.aspects.kubernetes.media.sabnzbd.k8s-manifests =
    { cluster, ... }:
    cluster.methods.mkMediaApp {
      name = "sabnzbd";
      servarr = false;
      # The image writes it into sabnzbd.ini at start.
      apiKeyEnv = "SABNZBD__API_KEY";
      # renovate: datasource=docker depName=ghcr.io/home-operations/sabnzbd
      tag = "5.1.3@sha256:07790a7829201d9ea302e8b862078beac4b1a07003fe8359e3f069b6bcd84a95";
      port = 8080;
      # The image writes these into sabnzbd.ini at start.
      env = {
        # After the pod's own hostname.
        SABNZBD__HOST_WHITELIST_ENTRIES = "sabnzbd.kidibox.net, sabnzbd.media.svc.cluster.local";
      };
      probePath = "/api?mode=version";
      # The CT's uid 330 behind the unprivileged-CT offset: what owns the
      # downloads on tank.
      uid = 100330;
      # The CT's own mount path, which sabnzbd.ini and the *arr apps'
      # completed-download paths refer to.
      hostPaths.downloads = {
        path = "/tank/downloads/sabnzbd";
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
      # SABnzbd's own network gate lets everything through: Kanidm is the
      # gate now, and it would refuse the public clients X-Forwarded-For
      # names.
      args = [
        "--inet_exposure"
        "4"
      ];
    };
}
