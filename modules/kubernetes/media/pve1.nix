# Plex, still on pve1 behind its own Caddy on 443, which the Sonarr instances
# and Radarr notify. Goes with it when it moves into the cluster.
{ lib, ... }:
let
  pve1Apps = {
    plex = "10.0.30.100";
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
