# prd environment's network client devices — DHCP static lease data, ported
# verbatim from the previously hand-written per-network lists in
# modules/routerosDevices/rb5009.nix. crs320's own entry lives in
# modules/routerosDevices/crs320.nix instead (single producer for a router's
# own data lives with the router).
{ den, ... }:
{
  den.devices = {
    # Management
    capxr0 = {
      network = "Management";
      hostNum = 10;
      mac = "48:a9:8a:cc:6d:62";
    };
    capxr1 = {
      network = "Management";
      hostNum = 11;
      mac = "48:a9:8a:ba:2a:6e";
    };
    # pikvm encodes the Servers VLAN id into its Management-space host
    # number (physically on Management, logically tied to per-server
    # numbering on Servers) — ported as-is, not a fix.
    pikvm = {
      network = "Management";
      hostNum = (den.networks.Servers.vlanId * 256) + 11;
      mac = "dc:a6:32:06:69:9a";
    };

    # Servers
    pve1 = {
      network = "Servers";
      hostNum = 11;
      mac = "be:4f:11:f4:ba:61";
    };
    homeassistant = {
      network = "Servers";
      hostNum = 101;
      mac = "52:54:00:93:9b:8f";
    };

    # Media
    cloudflared1 = {
      network = "Media";
      hostNum = 11;
      mac = "bc:24:11:bf:d2:cb";
    };
    truenas = {
      network = "Media";
      hostNum = 126;
      mac = "bc:24:11:9f:50:bf";
    };

    # Trusted
    "everything-presence-lite-20b1c4" = {
      network = "Trusted";
      hostNum = 108;
      mac = "08:d1:f9:20:b1:c4";
    };
    prtsrv = {
      network = "Trusted";
      hostNum = 137;
      mac = "bc:24:11:42:5b:fc";
    };
    shield = {
      network = "Trusted";
      hostNum = 212;
      mac = "48:b0:2d:18:ec:cd";
    };

    # IotLocal
    doorbell = {
      network = "IotLocal";
      hostNum = 10;
      mac = "ec:71:db:26:a9:37";
    };
    "litters camera" = {
      network = "IotLocal";
      hostNum = 11;
      mac = "e0:01:c7:e4:e0:f3";
    };
    LGwebOSTV = {
      network = "IotLocal";
      hostNum = 20;
      mac = "f0:86:20:10:84:18";
    };
    denon = {
      network = "IotLocal";
      hostNum = 21;
      mac = "00:06:78:40:24:0a";
    };
    "Somfy Box" = {
      network = "IotLocal";
      hostNum = 30;
      mac = "88:12:ac:04:36:44";
    };

    # IotInternet
    roborock-vacuum-a38 = {
      network = "IotInternet";
      hostNum = 30;
      mac = "b0:4a:39:98:1c:cb";
    };
    dreame_vacuum_r2465a = {
      network = "IotInternet";
      hostNum = 31;
      mac = "70:c9:32:4e:21:7d";
    };
  };
}
