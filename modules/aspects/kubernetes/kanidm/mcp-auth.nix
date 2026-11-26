# MCP servers in streamable HTTP mode, behind an Envoy JWT check for tokens
# Kanidm issued to the public `mcp` client (declared in victoria-metrics/mcp.nix).
# Clients discover it from the RFC 9728 metadata each host serves without auth.
# mkAuth takes { <Service name> = { hostname; port; route; }; } and returns an
# application module, for the application declaring HTTPRoute `route`. The
# server shares the host of the app it serves, and its /mcp and metadata rules
# join that app's route: one route per host, so one external-dns owner.
# The JWT check covers only the `mcp` rule. An app policy on the same route
# must target its own rule as well, or it also covers the metadata rules.
{ lib, ... }:
let
  clientId = "mcp";
  # Matches callbackPort in .mcp.json.
  callbackPort = 33418;
  scopes = [
    "openid"
    "profile"
    "email"
  ];
  mcpPath = "/mcp";
  # The route's rule the JWT check attaches to.
  mcpRule = "mcp";

  # Both well-known URIs MCP clients probe.
  metadataPath = "/.well-known/oauth-protected-resource";
  metadataDocuments = hostname: {
    root = {
      path = metadataPath;
      resource = "https://${hostname}";
    };
    mcp = {
      path = "${metadataPath}${mcpPath}";
      resource = "https://${hostname}${mcpPath}";
    };
  };
  metadataFilter = name: rule: "${name}-metadata-${rule}";

  mkAuth =
    kanidm: servers:
    let
      issuer = kanidm.issuer clientId;
      perServer = f: lib.concatMapAttrs f servers;
    in
    {
      resources = {
        httpRoutes = perServer (
          name:
          {
            hostname,
            port,
            route,
          }:
          {
            ${route}.spec.rules = [
              {
                name = mcpRule;
                matches = [
                  {
                    path = {
                      type = "PathPrefix";
                      value = mcpPath;
                    };
                  }
                ];
                backendRefs = [
                  {
                    group = "";
                    kind = "Service";
                    inherit name port;
                    weight = 1;
                  }
                ];
              }
            ]
            ++ (
              metadataDocuments hostname
              |> lib.mapAttrsToList (
                rule: document: {
                  name = "mcp-metadata-${rule}";
                  matches = [
                    {
                      path = {
                        type = "Exact";
                        value = document.path;
                      };
                    }
                  ];
                  filters = [
                    {
                      type = "ExtensionRef";
                      extensionRef = {
                        group = "gateway.envoyproxy.io";
                        kind = "HTTPRouteFilter";
                        name = metadataFilter name rule;
                      };
                    }
                  ];
                }
              )
            );
          }
        );

        httpRouteFilters = perServer (
          name:
          { hostname, ... }:
          metadataDocuments hostname
          |> lib.mapAttrs' (
            rule: document:
            lib.nameValuePair (metadataFilter name rule) {
              spec.directResponse = {
                contentType = "application/json";
                statusCode = 200;
                body = {
                  type = "Inline";
                  inline = builtins.toJSON {
                    inherit (document) resource;
                    authorization_servers = [ issuer ];
                    bearer_methods_supported = [ "header" ];
                    scopes_supported = scopes;
                  };
                };
              };
            }
          )
        );

        # Kanidm sets `aud` to the client name.
        securityPolicies.mcp.spec = {
          targetRefs = lib.mapAttrsToList (_: server: {
            group = "gateway.networking.k8s.io";
            kind = "HTTPRoute";
            name = server.route;
            sectionName = mcpRule;
          }) servers;
          jwt.providers = [
            {
              name = "kanidm";
              inherit issuer;
              audiences = [ clientId ];
              remoteJWKS.uri = "${issuer}/public_key.jwk";
            }
          ];
        };
      };
    };
in
{
  den.clusterMethods.mcp = cluster: {
    inherit
      clientId
      scopes
      callbackPort
      ;
    mkAuth = mkAuth cluster.methods.kanidm;
  };
}
