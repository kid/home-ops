# The apps still on pve1, behind their own Caddy on 443, that the cluster's
# media apps call: the Sonarr instances and Radarr send grabs to sabnzbd and
# notify Plex, and Prowlarr checks sabnzbd. Drop each app as it moves into
# the cluster, and this aspect with the last one.
{ lib, ... }:
let
  pve1Apps = {
    plex = "10.0.30.100";
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
    ];
}
