# MCP servers in streamable HTTP mode, behind an Envoy JWT check for tokens
# Kanidm issued to the public `mcp` client (declared in victoria-metrics/mcp.nix).
# Clients discover it from the RFC 9728 metadata each host serves without auth.
# mkAuth takes { <Service name> = { hostname; port; }; } and returns an
# application module, for that application's `imports`.
{ config, lib, ... }:
let
  inherit (config.den.clusters.prd.methods) kanidm;
  clientId = "mcp";
  issuer = kanidm.issuer clientId;
  # Matches callbackPort in .mcp.json.
  callbackPort = 33418;
  scopes = [
    "openid"
    "profile"
    "email"
  ];
  mcpPath = "/mcp";
  parentRefs = [
    {
      group = "gateway.networking.k8s.io";
      kind = "Gateway";
      name = "apps";
      namespace = "envoy-gateway-system";
      sectionName = "https";
    }
  ];

  # Both well-known URIs MCP clients probe. nixidy keys HTTPRoute rules by name, so they need one.
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
    servers:
    let
      perServer = f: lib.concatMapAttrs f servers;
    in
    {
      resources = {
        httpRoutes = perServer (
          name:
          { hostname, port }:
          {
            ${name}.spec = {
              inherit parentRefs;
              hostnames = [ hostname ];
              rules = [
                {
                  matches = [
                    {
                      path = {
                        type = "PathPrefix";
                        value = "/";
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
              ];
            };
            # A route of its own, so the SecurityPolicy below leaves it open.
            "${name}-metadata".spec = {
              inherit parentRefs;
              hostnames = [ hostname ];
              rules = lib.mapAttrsToList (rule: document: {
                name = rule;
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
              }) (metadataDocuments hostname);
            };
          }
        );

        httpRouteFilters = perServer (
          name:
          { hostname, ... }:
          lib.mapAttrs' (
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
          ) (metadataDocuments hostname)
        );

        # Kanidm sets `aud` to the client name.
        securityPolicies.mcp.spec = {
          targetRefs = lib.mapAttrsToList (name: _: {
            group = "gateway.networking.k8s.io";
            kind = "HTTPRoute";
            inherit name;
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
  den.clusters.prd.methods.mcp = {
    inherit
      clientId
      scopes
      callbackPort
      mkAuth
      ;
  };
}
