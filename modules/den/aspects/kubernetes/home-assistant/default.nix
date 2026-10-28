# Home Assistant runs outside the cluster (a VM on the Servers VLAN); this only
# publishes it through the Cloudflare tunnel. No Access app in front: HA has
# its own login.
{ config, ... }:
let
  haAddress = config.den.devices.homeassistant.address;
  hostname = "ha.kidibox.net";
  namespace = "home-assistant";
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
          dst_port = 443;
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
              toPorts = tcp [ 443 ];
            }
          ];
        };

      applications.home-assistant = {
        inherit namespace;

        # Through HA's nginx on 443, not HA itself on 8123: HA rejects X-Forwarded-For from untrusted proxies.
        # ExternalName, not an EndpointSlice: ArgoCD excludes EndpointSlices from sync.
        # rb5009's static DNS entry resolves the name to the LAN address.
        # ExternalBackend can't be used: the tunnel proxy only passes WebSocket upgrades
        # for a Service port with a ws/wss appProtocol, and HA's frontend needs them.
        resources.services.home-assistant.spec = {
          type = "ExternalName";
          externalName = hostname;
          ports = [
            {
              name = "https";
              port = 443;
              protocol = "TCP";
              appProtocol = "kubernetes.io/wss";
            }
          ];
        };

        # The tunnel proxy only trusts explicit caCertificateRefs, not the system roots; HA's certificate is Let's Encrypt.
        resources.bundles.public-ca.spec = {
          sources = [ { useDefaultCAs = true; } ];
          target = {
            configMap.key = "ca.crt";
            namespaceSelector.matchLabels."kubernetes.io/metadata.name" = namespace;
          };
        };

        resources.backendTLSPolicies.home-assistant.spec = {
          targetRefs = [
            {
              kind = "Service";
              name = "home-assistant";
              group = "";
            }
          ];
          validation = {
            inherit hostname;
            caCertificateRefs = [
              {
                kind = "ConfigMap";
                name = "public-ca";
                group = "";
              }
            ];
          };
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
                  port = 443;
                  weight = 1;
                }
              ];
            }
          ];
        };
      };
    };
}
