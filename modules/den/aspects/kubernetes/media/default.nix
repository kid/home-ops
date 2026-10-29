# Media apps running outside the cluster (on the Media VLAN), published on the
# internal "apps" Gateway only; internal external-dns points their hostnames at
# it. Kanidm gates them, so app-to-app calls must use their LAN addresses.
{ config, lib, ... }:
let
  media = config.den.environments.prd.networks.Media.methods.host;
  apps = {
    prowlarr = {
      address = media 110;
      port = 9696;
    };
    radarr = {
      address = media 120;
      port = 7878;
    };
    sonarr = {
      address = media 130;
      port = 8989;
    };
    sabnzbd = {
      address = media 150;
      port = 8080;
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

        resources.httpRoutes = lib.mapAttrs (name: _: {
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
        }) apps;
      };
    };
}
