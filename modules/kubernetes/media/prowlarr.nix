# Prowlarr, the indexer manager the *arr apps search through, moved from
# pve1's CT 110, whose config was imported once into the kopiur-backed volume.
{ config, lib, ... }:
let
  # renovate: datasource=docker depName=ghcr.io/home-operations/prowlarr
  tag = "3.0.0.5737@sha256:0954599432e16ccd86129f1eb8eb0247fd0d1591aab400f73e2010a1cda37be8";

  # Still on pve1 behind their own Caddy: Prowlarr syncs its indexers into
  # them and sends grabs to sabnzbd, and they call it back through the apps
  # Gateway. Drop each one as it moves into the cluster.
  pve1Apps = {
    radarr = "10.0.30.120";
    sonarr = "10.0.30.130";
    animarr = "10.0.30.140";
    sabnzbd = "10.0.30.150";
  };
in
{
  den.aspects.kubernetes.media.prowlarr.firewall =
    { cluster, ... }:
    [
      {
        inherit (cluster) network;
        forward =
          pve1Apps
          |> lib.mapAttrsToList (
            app: address: {
              action = "accept";
              dst_address = address;
              dst_port = 443;
              protocol = "tcp";
              comment = "Allow prowlarr in K3s to reach ${app} on pve1";
            }
          );
      }
      {
        network = config.den.networks.Media.name;
        forward = [
          {
            action = "accept";
            dst_address = cluster.networks.loadBalancer.cidr;
            dst_port = 443;
            protocol = "tcp";
            comment = "Allow the *arr apps on pve1 to reach prowlarr in K3s";
          }
        ];
      }
    ];

  den.aspects.kubernetes.media.prowlarr.k8s-manifests =
    { cluster, ... }:
    {
      applications.prowlarr = cluster.methods.mkMediaApp {
        name = "prowlarr";
        inherit tag;
        port = 9696;
        # The image runs as any uid.
        uid = 1000;
        replicas = 1;
      };
    };
}
