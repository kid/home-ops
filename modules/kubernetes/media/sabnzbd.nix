# SABnzbd, the Usenet downloader the *arr apps send grabs to, moved from
# pve1's CT 150, whose config was imported once into the kopiur-backed
# volume.
{ config, ... }:
{
  den.aspects.kubernetes.media.sabnzbd.k8s-manifests =
    { cluster, ... }:
    {
      applications.sabnzbd = cluster.methods.mkMediaApp {
        name = "sabnzbd";
        servarr = false;
        # The image writes it into sabnzbd.ini at start.
        apiKeyEnv = "SABNZBD__API_KEY";
        # renovate: datasource=docker depName=ghcr.io/home-operations/sabnzbd
        tag = "5.1.3@sha256:c89b0322721c3eba47221e5f916505e7e742684651f73c5215717340b6b5402f";
        port = 8080;
        # The image writes these into sabnzbd.ini at start.
        env = {
          # After the pod's own hostname.
          SABNZBD__HOST_WHITELIST_ENTRIES = "sabnzbd.kidibox.net, sabnzbd.media.svc.cluster.local";
          # Replaces SABnzbd's default (any private address) wholesale, and
          # it checks X-Forwarded-For against it too: the pod network for the
          # connection itself (Envoy, the other apps, the kubelet's probes
          # through cilium_host; outside 172.16.0.0/12), and the home
          # networks for the browsers Envoy forwards.
          SABNZBD__LOCAL_RANGES_ENTRIES = "${cluster.networks.pods.cidr}, ${
            config.den.environments.${cluster.environment}.cidrBase
          }";
        };
        probePath = "/api?mode=version";
        # The CT's uid 330 behind the unprivileged-CT offset: what owns the
        # downloads on tank.
        uid = 100330;
        # The CT's own mount path, which sabnzbd.ini and the *arr apps'
        # completed-download paths refer to.
        nfs.downloads = {
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
      };
    };
}
