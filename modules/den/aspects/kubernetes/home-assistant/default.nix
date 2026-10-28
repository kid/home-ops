# Home Assistant runs outside the cluster (a VM on the Servers VLAN); this only
# publishes it through the Cloudflare tunnel. No Access app in front: HA has
# its own login.
{ config, ... }:
let
  haAddress = config.den.devices.homeassistant.address;
  haPort = 8123;
  hostname = "ha.kidibox.net";
in
{
  # RouterOS access this app needs — see modules/den/quirks/firewall.nix.
  den.aspects.kubernetes.home-assistant.firewall = { cluster, ... }: [
    {
      inherit (cluster) network;
      forward = [
        {
          action = "accept";
          dst_address = haAddress;
          dst_port = haPort;
          protocol = "tcp";
          comment = "Allow access to HomeAssistant from K3s for the Cloudflare tunnel";
        }
      ];
    }
  ];

  den.aspects.kubernetes.home-assistant.k8s-manifests =
    { cluster, ... }:
    {
      applications.cloudflare-tunnel-gateway.resources.ciliumNetworkPolicies.cloudflare-tunnel-home-assistant =
        with cluster.methods.netpol;
        mkPolicy { "app.kubernetes.io/name" = "cloudflare-tunnel-gateway-controller-proxy"; } {
          egress = [
            {
              toCIDR = [ "${haAddress}/32" ];
              toPorts = tcp [ haPort ];
            }
          ];
        };

      applications.home-assistant = {
        namespace = "home-assistant";

        # Straight to HA, whose trusted_proxies must list the K3s node addresses
        # (Cilium masquerades traffic leaving the pod CIDR).
        # ExternalName, not an EndpointSlice: ArgoCD excludes EndpointSlices from sync.
        # rb5009's static DNS entry resolves the name to the LAN address.
        # ExternalBackend can't be used: the tunnel proxy only passes WebSocket upgrades
        # for a Service port with a ws/wss appProtocol, and HA's frontend needs them.
        resources.services.home-assistant.spec = {
          type = "ExternalName";
          externalName = hostname;
          ports = [
            {
              name = "http";
              port = haPort;
              protocol = "TCP";
              appProtocol = "kubernetes.io/ws";
            }
          ];
        };

        resources.httpRoutes.home-assistant.metadata.labels."home-ops.dev/public-dns" = "true";
        resources.httpRoutes.home-assistant.spec = {
          parentRefs = [
            {
              group = "gateway.networking.k8s.io";
              kind = "Gateway";
              name = "cloudflare-tunnel";
              namespace = "cloudflare-tunnel-system";
              sectionName = "http";
            }
          ];
          hostnames = [ hostname ];
          rules = [
            {
              backendRefs = [
                {
                  group = "";
                  kind = "Service";
                  name = "home-assistant";
                  port = haPort;
                  weight = 1;
                }
              ];
            }
          ];
        };
      };
    };
}
