# prd environment's network client devices — DHCP static lease data, ported
# verbatim from the previously hand-written per-network lists in
# modules/den/routerosDevices/rb5009.nix. crs320's own entry lives in
# modules/den/routerosDevices/crs320.nix instead (single producer for a router's
# own data lives with the router).
{ den, ... }:
{
  den.devices = {
    # Management
    capxr0 = {
      mac = "48:a9:8a:cc:6d:62";
      interfaces = [
        {
          network = "Management";
          hostNum = 10;
        }
      ];
    };
    capxr1 = {
      mac = "48:a9:8a:ba:2a:6e";
      interfaces = [
        {
          network = "Management";
          hostNum = 11;
        }
      ];
    };
    # pikvm encodes the Servers VLAN id into its Management-space host
    # number (physically on Management, logically tied to per-server
    # numbering on Servers) — ported as-is, not a fix.
    pikvm = {
      mac = "dc:a6:32:06:69:9a";
      interfaces = [
        {
          network = "Management";
          hostNum = (den.networks.Servers.vlanId * 256) + 11;
        }
      ];
    };

    # Servers
    pve1 = {
      mac = "be:4f:11:f4:ba:61";
      interfaces = [
        {
          network = "Servers";
          hostNum = 11;
        }
      ];
    };
    homeassistant = {
      mac = "52:54:00:93:9b:8f";
      interfaces = [
        {
          network = "Servers";
          hostNum = 101;
        }
      ];
    };

    # Media
    cloudflared1 = {
      mac = "bc:24:11:bf:d2:cb";
      interfaces = [
        {
          network = "Media";
          hostNum = 11;
        }
      ];
    };
    truenas = {
      mac = "bc:24:11:9f:50:bf";
      interfaces = [
        {
          network = "Media";
          hostNum = 126;
        }
        {
          network = "Storage";
          hostNum = 126;
        }
      ];
    };

    # Trusted
    "everything-presence-lite-20b1c4" = {
      mac = "08:d1:f9:20:b1:c4";
      interfaces = [
        {
          network = "Trusted";
          hostNum = 108;
        }
      ];
    };
    prtsrv = {
      mac = "bc:24:11:42:5b:fc";
      interfaces = [
        {
          network = "Trusted";
          hostNum = 137;
        }
      ];
    };
    shield = {
      mac = "48:b0:2d:18:ec:cd";
      interfaces = [
        {
          network = "Trusted";
          hostNum = 212;
        }
      ];
    };

    # IotLocal
    doorbell = {
      mac = "ec:71:db:26:a9:37";
      interfaces = [
        {
          network = "IotLocal";
          hostNum = 10;
        }
      ];
    };
    "litters camera" = {
      mac = "e0:01:c7:e4:e0:f3";
      interfaces = [
        {
          network = "IotLocal";
          hostNum = 11;
        }
      ];
    };
    LGwebOSTV = {
      mac = "f0:86:20:10:84:18";
      interfaces = [
        {
          network = "IotLocal";
          hostNum = 20;
        }
      ];
    };
    denon = {
      mac = "00:06:78:40:24:0a";
      interfaces = [
        {
          network = "IotLocal";
          hostNum = 21;
        }
      ];
    };
    "Somfy Box" = {
      mac = "88:12:ac:04:36:44";
      interfaces = [
        {
          network = "IotLocal";
          hostNum = 30;
        }
      ];
    };

    # IotInternet
    roborock-vacuum-a38 = {
      mac = "b0:4a:39:98:1c:cb";
      interfaces = [
        {
          network = "IotInternet";
          hostNum = 30;
        }
      ];
    };
    dreame_vacuum_r2465a = {
      mac = "70:c9:32:4e:21:7d";
      interfaces = [
        {
          network = "IotInternet";
          hostNum = 31;
        }
      ];
    };
  };
}
