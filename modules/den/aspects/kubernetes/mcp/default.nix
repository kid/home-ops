# VictoriaMetrics and VictoriaLogs MCP servers in streamable HTTP mode, behind
# an Envoy JWT check for tokens Kanidm issued to the public `mcp` client. Clients
# discover it from the RFC 9728 metadata each host serves without auth.
_: {
  den.aspects.kubernetes.mcp.k8s-manifests =
    {
      cluster,
      lib,
      ...
    }:
    let
      inherit (cluster.methods) kanidm;
      namespace = "mcp";
      clientId = "mcp";
      issuer = kanidm.issuer clientId;
      # Matches callbackPort in .mcp.json.
      callbackPort = 33418;
      scopes = [
        "openid"
        "profile"
        "email"
      ];
      port = 8080;
      mcpPath = "/mcp";
      appId = 1000;

      servers = {
        mcp-victoriametrics = {
          host = "mcp-metrics";
          # renovate: datasource=docker depName=ghcr.io/victoriametrics/mcp-victoriametrics
          tag = "1.20.2@sha256:bcbf84f945d6efb03fb8b2d2ccc3294420dccdc0b445752dce96f02619416dfe";
          env = {
            VM_INSTANCE_ENTRYPOINT = "http://vmsingle-victoria-metrics.monitoring.svc:8428";
            VM_INSTANCE_TYPE = "single";
          };
          backend = {
            name = "vmsingle";
            port = 8428;
          };
        };
        mcp-victorialogs = {
          host = "mcp-logs";
          # renovate: datasource=docker depName=ghcr.io/victoriametrics/mcp-victorialogs
          tag = "1.9.0@sha256:753bb4fbe402ca1a782842f44636830f9895736f11d7fe783b924f8a0daf083d";
          env.VL_INSTANCE_ENTRYPOINT = "http://vlsingle-victoria-metrics.monitoring.svc:9428";
          backend = {
            name = "vlsingle";
            port = 9428;
          };
        };
      };

      labels = name: { "app.kubernetes.io/name" = name; };
      hostname = server: cluster.methods.mkAppHostname server.host;
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
      metadataDocuments = server: {
        root = {
          path = metadataPath;
          resource = "https://${hostname server}";
        };
        mcp = {
          path = "${metadataPath}${mcpPath}";
          resource = "https://${hostname server}${mcpPath}";
        };
      };
      metadataFilter = name: rule: "${name}-metadata-${rule}";

      perServer = f: lib.concatMapAttrs f servers;
    in
    {
      applications.mcp = {
        inherit namespace;

        resources = {
          ciliumNetworkPolicies =
            with cluster.methods.netpol;
            perServer (
              name: server: {
                ${name} = mkPolicy (labels name) {
                  ingress = [ (gatewayIngress port) ];
                  egress = [ (toNamespace "monitoring" (labels server.backend.name) [ server.backend.port ]) ];
                };
              }
            );

          deployments = perServer (
            name: server: {
              ${name}.spec = {
                replicas = 1;
                selector.matchLabels = labels name;
                template = {
                  metadata.labels = labels name;
                  spec = {
                    automountServiceAccountToken = false;
                    securityContext = {
                      runAsNonRoot = true;
                      runAsUser = appId;
                      runAsGroup = appId;
                      seccompProfile.type = "RuntimeDefault";
                    };
                    containers.${name} = {
                      image = "ghcr.io/victoriametrics/${name}:${server.tag}";
                      env = lib.mapAttrs (_: value: { inherit value; }) (
                        server.env
                        // {
                          MCP_SERVER_MODE = "http";
                          MCP_LISTEN_ADDR = ":${toString port}";
                        }
                      );
                      ports.http.containerPort = port;
                      livenessProbe.httpGet = {
                        path = "/health/liveness";
                        port = "http";
                      };
                      readinessProbe.httpGet = {
                        path = "/health/readiness";
                        port = "http";
                      };
                      securityContext = {
                        allowPrivilegeEscalation = false;
                        readOnlyRootFilesystem = true;
                        capabilities.drop = [ "ALL" ];
                      };
                      resources = {
                        requests = {
                          cpu = "10m";
                          memory = "32Mi";
                        };
                        limits.memory = "128Mi";
                      };
                    };
                  };
                };
              };
            }
          );

          services = perServer (
            name: _: {
              ${name}.spec = {
                selector = labels name;
                ports.http = {
                  inherit port;
                  targetPort = "http";
                };
              };
            }
          );

          httpRoutes = perServer (
            name: server: {
              ${name}.spec = {
                inherit parentRefs;
                hostnames = [ (hostname server) ];
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
                hostnames = [ (hostname server) ];
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
                }) (metadataDocuments server);
              };
            }
          );

          httpRouteFilters = perServer (
            name: server:
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
            ) (metadataDocuments server)
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

          kanidmOAuth2Clients.${clientId}.spec = {
            kanidmRef = kanidm.ref;
            displayname = "MCP servers";
            public = true;
            allowLocalhostRedirect = true;
            origin = "http://localhost:${toString callbackPort}";
            redirectUrl = [ "http://localhost:${toString callbackPort}/callback" ];
            scopeMap = [
              {
                group = "admins";
                inherit scopes;
              }
            ];
          };
        };
      };
    };
}
