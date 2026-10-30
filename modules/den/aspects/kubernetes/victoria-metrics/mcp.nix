# VictoriaMetrics and VictoriaLogs MCP servers, behind cluster.methods.mcp's
# Kanidm JWT check (kanidm/mcp-auth.nix). Owns the cluster's one public `mcp`
# Kanidm client, which every MCP server's tokens come from.
_: {
  den.aspects.kubernetes.victoria-metrics-mcp.k8s-manifests =
    {
      cluster,
      lib,
      ...
    }:
    let
      inherit (cluster.methods) kanidm mcp;
      port = 8080;
      appId = 1000;

      servers = {
        mcp-victoriametrics = {
          host = "metrics";
          # renovate: datasource=docker depName=ghcr.io/victoriametrics/mcp-victoriametrics
          tag = "1.20.2@sha256:bcbf84f945d6efb03fb8b2d2ccc3294420dccdc0b445752dce96f02619416dfe";
          env = {
            VM_INSTANCE_ENTRYPOINT = "http://vmsingle-victoria-metrics.monitoring.svc:8428";
            VM_INSTANCE_TYPE = "single";
            # Upstream's defaults plus documentation, whose in-memory docs index needs ~512 MiB.
            MCP_DISABLED_TOOLS = "export,flags,metric_relabel_debug,downsampling_filters_debug,retention_filters_debug,test_rules,documentation";
          };
          backend = {
            name = "vmsingle";
            port = 8428;
          };
        };
        mcp-victorialogs = {
          host = "logs";
          # renovate: datasource=docker depName=ghcr.io/victoriametrics/mcp-victorialogs
          tag = "1.9.0@sha256:753bb4fbe402ca1a782842f44636830f9895736f11d7fe783b924f8a0daf083d";
          env = {
            VL_INSTANCE_ENTRYPOINT = "http://vlsingle-victoria-metrics.monitoring.svc:9428";
            # No default list upstream. Also skips the docs resources, whose
            # in-memory index outgrows the 128Mi limit.
            MCP_DISABLED_TOOLS = "documentation";
          };
          backend = {
            name = "vlsingle";
            port = 9428;
          };
        };
      };

      labels = name: { "app.kubernetes.io/name" = name; };

      perServer = f: lib.concatMapAttrs f servers;
    in
    {
      applications.victoria-metrics = {
        # kaniop's webhook admits the MCP client.
        flux.dependsOn = [ "kaniop" ];
        imports = [
          (mcp.mkAuth (
            lib.mapAttrs (_: server: {
              hostname = cluster.methods.mkAppHostname server.host;
              inherit port;
            }) servers
          ))
        ];

        resources = {
          ciliumNetworkPolicies =
            with cluster.methods.netpol;
            perServer (
              name: server: {
                ${name} = mkPolicy (labels name) {
                  ingress = [ (gatewayIngress port) ];
                  egress = [ (toPods (labels server.backend.name) [ server.backend.port ]) ];
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

          kanidmOAuth2Clients.${mcp.clientId}.spec = {
            kanidmRef = kanidm.ref;
            displayname = "MCP servers";
            public = true;
            allowLocalhostRedirect = true;
            origin = "http://localhost:${toString mcp.callbackPort}";
            redirectUrl = [ "http://localhost:${toString mcp.callbackPort}/callback" ];
            scopeMap = [
              {
                group = "admins";
                inherit (mcp) scopes;
              }
            ];
          };
        };
      };
    };
}
