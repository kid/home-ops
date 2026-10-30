# Media apps running outside the cluster (on the Media VLAN), published on the
# internal "apps" Gateway only; internal external-dns points their hostnames at it.
# Kanidm gates the UIs; the API paths stay open for app-to-app calls, which the
# apps authenticate with their API keys.
{ config, lib, ... }:
let
  inherit (config.den.environments.prd.networks) Media;
  media = Media.methods.host;
  apiPrefix = {
    path = {
      type = "PathPrefix";
      value = "/api";
    };
  };
  apps = {
    prowlarr = {
      address = media 110;
      port = 9696;
      # Indexer proxies the other apps sync from Prowlarr: /<id>/api, /<id>/download.
      apiMatches = [
        apiPrefix
        {
          path = {
            type = "RegularExpression";
            value = "/[0-9]+/(api|download)(/.*)?";
          };
        }
      ];
    };
    radarr = {
      address = media 120;
      port = 7878;
      apiMatches = [ apiPrefix ];
    };
    sonarr = {
      address = media 130;
      port = 8989;
      apiMatches = [ apiPrefix ];
    };
    sabnzbd = {
      address = media 150;
      port = 8080;
      apiMatches = [ apiPrefix ];
    };
  };
in
{
  # RouterOS access these apps need — see modules/den/quirks/firewall.nix.
  den.aspects.kubernetes.media.firewall = { cluster, ... }: [
    {
      inherit (cluster) network;
      forward = lib.mapAttrsToList (name: app: {
        action = "accept";
        dst_address = app.address;
        dst_port = app.port;
        protocol = "tcp";
        comment = "Allow access to ${name} from K3s for Envoy Gateway";
      }) apps;
    }
    # The apps reach each other by hostname, through the Gateway.
    {
      network = Media.name;
      forward = [
        {
          action = "accept";
          dst_address = cluster.networks.loadBalancer.cidr;
          dst_port = 443;
          protocol = "tcp";
          comment = "Allow access to the cluster apps from Media";
        }
      ];
    }
  ];

  den.aspects.kubernetes.media.k8s-manifests =
    { cluster, ... }:
    {
      applications.envoy-gateway.resources.ciliumNetworkPolicies.envoy-proxy-media =
        with cluster.methods.netpol;
        mkPolicy { "app.kubernetes.io/name" = "envoy"; } {
          egress = lib.mapAttrsToList (_: app: {
            toCIDR = [ "${app.address}/32" ];
            toPorts = tcp [ app.port ];
          }) apps;
        };

      applications.media = {
        namespace = "media";

        imports = lib.mapAttrsToList (
          name: _:
          cluster.methods.mkOidcAuth {
            inherit name;
            httpRouteName = name;
            hostname = cluster.methods.mkAppHostname name;
            group = "media";
          }
        ) apps;

        # Envoy Gateway rejects ExternalName Services and ArgoCD skips EndpointSlices, hence its Backend API.
        resources.backends = lib.mapAttrs (_: app: {
          spec.endpoints = [ { ip = { inherit (app) address port; }; } ];
        }) apps;

        resources.httpRoutes =
          let
            mkRoute = name: matches: {
              spec = {
                parentRefs = [
                  {
                    group = "gateway.networking.k8s.io";
                    kind = "Gateway";
                    name = "apps";
                    namespace = "envoy-gateway-system";
                    sectionName = "https";
                  }
                ];
                hostnames = [ (cluster.methods.mkAppHostname name) ];
                rules = [
                  {
                    inherit matches;
                    backendRefs = [
                      {
                        group = "gateway.envoyproxy.io";
                        kind = "Backend";
                        inherit name;
                        weight = 1;
                      }
                    ];
                  }
                ];
              };
            };
          in
          lib.concatMapAttrs (name: app: {
            # Gated by mkOidcAuth above.
            ${name} = mkRoute name [
              {
                path = {
                  type = "PathPrefix";
                  value = "/";
                };
              }
            ];
            # No SecurityPolicy: the more specific match wins over the UI route.
            "${name}-api" = mkRoute name app.apiMatches;
          }) apps;
      };
    };
}
