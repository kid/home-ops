# Plex, moved from pve1's CT 100, whose config was imported once into the
# kopiur-backed volume.
{ config, lib, ... }:
let
  # Where the image keeps Plex's data, under /config.
  dataDir = "/Library/Application Support/Plex Media Server";
in
{
  den.aspects.kubernetes.media.plex.k8s-manifests =
    { cluster, ... }:
    {
      applications.plex = cluster.methods.mkMediaApp {
        name = "plex";
        servarr = false;
        # renovate: datasource=docker depName=ghcr.io/home-operations/plex
        tag = "1.43.5.11079@sha256:06ef0fc23e9af9bbaf284c3f27972f94e703d13d6f745edeb6818fcbebf6c673";
        port = 32400;
        probePath = "/identity";
        # The entrypoint writes these into Preferences.xml at start.
        env = {
          # What plex.tv hands clients to connect to.
          PLEX_ADVERTISE_URL = "https://${cluster.methods.mkAppHostname "plex"}:443";
          # Clients reach it through Envoy, from the pod network; the home
          # networks for anything that passes their address along.
          PLEX_PREFERENCE_1 = "LanNetworksBandwidth=${
            lib.concatStringsSep "," [
              cluster.networks.pods.cidr
              config.den.environments.${cluster.environment}.cidrBase
            ]
          }";
          # The image defaults to /transcode, which isn't mounted.
          PLEX_PREFERENCE_2 = "TranscoderTempDirectory=/tmp";
          # Its SSDP discovery can't leave the pod network.
          PLEX_PREFERENCE_3 = "DlnaEnabled=0";
          # kopiur backs the databases up.
          PLEX_PREFERENCE_4 = "ButlerTaskBackupDatabase=0";
          # The CT served its own certificate for plex.kidibox.net, from a file
          # the pod doesn't have; Envoy terminates TLS for that name now.
          PLEX_PREFERENCE_5 = "customCertificatePath=";
          PLEX_PREFERENCE_6 = "customCertificateKey=";
          PLEX_PREFERENCE_7 = "customCertificateDomain=";
        };
        # The CT's uid 490 behind the unprivileged-CT offset, which owns its
        # imported files.
        uid = 100490;
        # The CT's own mount path, which the library's paths in its database
        # refer to. Plex only reads it.
        nfs.library = {
          path = "/tank/library";
          mountPath = "/tank/library";
          readOnly = true;
        };
        # Its databases plus ~15G of artwork and chapter images.
        storage = "40Gi";
        memoryLimit = "4Gi";
        # Direct play streams whole files in one response.
        requestTimeout = "0s";
        # Only the databases and preferences go to R2; the rest is
        # re-downloaded or regenerated.
        backupIgnore = map (p: "${dataDir}/${p}") [
          "Metadata"
          "Media"
          "Cache"
          "Codecs"
          "Drivers"
          "Logs"
          "Crash Reports"
          "Updates"
          "Plug-in Support/Caches"
          "Plug-in Support/Databases/*.db-20*"
          "Plug-in Support/Databases/com.plexapp.dlna.db*"
        ];
      };
    };
}
