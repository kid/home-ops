# Home Assistant runs outside the cluster (a VM on the Servers VLAN); this only
# publishes it through the Cloudflare tunnel. HA has its own login, and its
# http.trusted_proxies must list the K3s node addresses (Cilium masquerades
# traffic leaving the pod CIDR).
{ config, ... }:
let
  address = config.den.devices.homeassistant.address;
  port = 8123;
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
          dst_address = address;
          dst_port = port;
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
              toCIDR = [ "${address}/32" ];
              toPorts = tcp [ port ];
            }
          ];
        };

      applications.home-assistant = {
        namespace = "home-assistant";

        # The tunnel proxy only passes WebSocket upgrades to a Service port with a
        # ws appProtocol, so an ExternalBackend can't be used.
        resources.services.home-assistant.spec.ports = [
          {
            name = "http";
            inherit port;
            protocol = "TCP";
            appProtocol = "kubernetes.io/ws";
          }
        ];

        # The Service has no selector: list HA's address by hand.
        resources.endpointSlices.home-assistant = {
          metadata.labels = {
            "kubernetes.io/service-name" = "home-assistant";
            "endpointslice.kubernetes.io/managed-by" = "home-ops";
          };
          addressType = "IPv4";
          ports = [
            {
              name = "http";
              inherit port;
              protocol = "TCP";
              appProtocol = "kubernetes.io/ws";
            }
          ];
          endpoints = [
            {
              addresses = [ address ];
              conditions.ready = true;
            }
          ];
        };

        resources.httpRoutes.home-assistant = {
          metadata.labels."home-ops.dev/public-dns" = "true";
          spec = {
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
                    inherit port;
                    weight = 1;
                  }
                ];
              }
            ];
          };
        };
      };
    };
}
