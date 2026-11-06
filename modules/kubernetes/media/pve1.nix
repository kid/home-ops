# The apps still on pve1, behind their own Caddy on 443, and the cluster's
# media apps that call each other across the move: prowlarr syncs indexers
# into radarr, the Sonarr instances send grabs to sabnzbd and notify Plex,
# and radarr calls prowlarr through the apps Gateway. Drop each app as it
# moves into the cluster, and this aspect with the last one.
{ config, lib, ... }:
let
  pve1Apps = {
    plex = "10.0.30.100";
    radarr = "10.0.30.120";
    sabnzbd = "10.0.30.150";
  };
in
{
  den.aspects.kubernetes.media.pve1.firewall =
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
              comment = "Allow K3s to reach ${app} on pve1";
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
            comment = "Allow the apps on pve1 to reach the apps Gateway in K3s";
          }
        ];
      }
    ];
}
