# Public routes take one of two paths. An HTTPRoute on the cloudflare-tunnel
# Gateway can go straight to an app's Service (home-assistant), which then
# bypasses the apps Gateway. mkGatewayTunnelRoute's route instead hands the
# request to the apps Gateway's Envoy, which serves it through the app's own
# route there: its SecurityPolicies (envoy-oidc.nix, mcp-auth.nix), timeouts
# and filters apply from outside too.
_:
let
  gatewayNamespace = "envoy-gateway-system";
  gatewayService = "apps-tunnel";
  # Let's Encrypt's roots, which sign wildcard-tls. The tunnel proxy only takes
  # explicit CA references, no system roots, and the controller copies the
  # bundle into every route's config, which its proxies cap at 1 MiB: the
  # system bundle stopped fitting at 11 routes.
  caRoots = "letsencrypt-roots";
  # The SNI the tunnel proxy sends to Envoy. The apps Gateway has a single
  # listener and certificate, so Envoy routes by Host whatever the SNI, as long
  # as wildcard-tls covers it.
  sni = cluster: cluster.methods.mkAppHostname "apps-gateway";
in
{
  den.clusterMethods.mkGatewayTunnelRoute = _: hostname: {
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
              name = gatewayService;
              port = 443;
              weight = 1;
            }
          ];
        }
      ];
    };
  };

  den.aspects.kubernetes.cloudflared.k8s-manifests =
    {
      charts,
      cluster,
      ...
    }:
    {
      applications.cloudflare-tunnel-gateway = {
        namespace = "cloudflare-tunnel-system";
        flux.dependsOn = [ "external-secrets-config" ];

        helm.releases.cloudflare-tunnel-gateway-controller = {
          chart = charts.lexfrei.cloudflare-tunnel-gateway-controller;
          values = {
            gatewayClassConfig = {
              create = true;
              tunnelID = cluster.cloudflare.tunnelId;
              cloudflareCredentialsSecretRef.name = "cloudflare-tunnel-api-token";
            };
            proxy.tunnelTokenSecretRef.name = "cloudflare-tunnel-connector-token";
            # limits.cpu = null drops the chart's default CPU limit.
            resources = {
              requests = {
                cpu = "10m";
                memory = "128Mi";
              };
              limits = {
                cpu = null;
                memory = "256Mi";
              };
            };
            proxy.resources = {
              requests = {
                cpu = "10m";
                memory = "64Mi";
              };
              limits = {
                cpu = null;
                memory = "128Mi";
              };
            };
          };
        };

        resources = {
          ciliumNetworkPolicies =
            with cluster.methods.netpol;
            let
              proxy = {
                "app.kubernetes.io/name" = "cloudflare-tunnel-gateway-controller-proxy";
              };
            in
            {
              cloudflare-tunnel-gateway-controller =
                mkPolicy { "app.kubernetes.io/name" = "cloudflare-tunnel-gateway-controller"; }
                  {
                    egress = [
                      apiserverEgress
                      (fqdnEgress [ "api.cloudflare.com" ] [ 443 ])
                      (toPods proxy [ 8081 ])
                    ];
                  };
              cloudflare-tunnel-gateway-controller-proxy = mkPolicy proxy {
                egress = [
                  {
                    toEntities = [ "world" ];
                    toPorts = tcpUdp [ 7844 ];
                  }
                  clusterEgress
                ];
              };
            };

          externalSecrets.cloudflare-tunnel-api-token.spec = {
            secretStoreRef = {
              name = "onepassword";
              kind = "ClusterSecretStore";
            };
            target.name = "cloudflare-tunnel-api-token";
            data = [
              {
                secretKey = "api-token";
                remoteRef.key = "cloudflared-tunnel-credentials/credentials/api-token";
              }
            ];
          };

          externalSecrets.cloudflare-tunnel-connector-token.spec = {
            secretStoreRef = {
              name = "onepassword";
              kind = "ClusterSecretStore";
            };
            target.name = "cloudflare-tunnel-connector-token";
            data = [
              {
                secretKey = "tunnel-token";
                remoteRef.key = "cloudflared-tunnel-credentials/credentials/tunnel-token";
              }
            ];
          };

          gateways.cloudflare-tunnel.spec = {
            gatewayClassName = "cloudflare-tunnel";
            listeners = [
              {
                name = "http";
                protocol = "HTTP";
                port = 80;
                allowedRoutes.namespaces.from = "All";
              }
            ];
          };
        };
      };

      # mkGatewayTunnelRoute's backend: the apps Gateway's Envoy pods, on a
      # ClusterIP Service of its own (Envoy Gateway names its LoadBalancer
      # after a hash). The wss appProtocol makes the tunnel proxy pass
      # WebSocket upgrades, over TLS.
      applications.envoy-gateway.resources = {
        services.${gatewayService}.spec = {
          selector = {
            "app.kubernetes.io/name" = "envoy";
            "gateway.envoyproxy.io/owning-gateway-name" = "apps";
            "gateway.envoyproxy.io/owning-gateway-namespace" = gatewayNamespace;
          };
          ports = [
            {
              name = "https";
              port = 443;
              # Envoy Gateway remaps privileged listener ports to 10000 + port.
              targetPort = 10443;
              protocol = "TCP";
              appProtocol = "kubernetes.io/wss";
            }
          ];
        };

        backendTLSPolicies.${gatewayService}.spec = {
          targetRefs = [
            {
              group = "";
              kind = "Service";
              name = gatewayService;
            }
          ];
          validation = {
            hostname = sni cluster;
            caCertificateRefs = [
              {
                group = "";
                kind = "ConfigMap";
                name = caRoots;
              }
            ];
          };
        };

        configMaps.${caRoots}.data."ca.crt" = builtins.readFile ./isrg-roots.pem;
      };
    };
}
