# Argo CD MCP server (argoproj-labs/mcp-for-argocd) at /mcp on ArgoCD's own
# host, behind cluster.methods.mcp's Kanidm JWT check, as local account `mcp`:
# role:readonly plus sync (which also covers terminating one). Needs
# victoria-metrics-mcp for the `mcp` Kanidm client and the argocd terragrunt
# stack for its token.
_: {
  den.aspects.kubernetes.argocd-mcp.k8s-manifests =
    { cluster, ... }:
    let
      name = "mcp-argocd";
      port = 3000;
      # The image's USER.
      appId = 1000;
      account = "mcp";
      hostname = cluster.methods.mkAppHostname "argocd";
      labels = {
        "app.kubernetes.io/name" = name;
      };
      # renovate: datasource=docker depName=ghcr.io/argoproj-labs/mcp-for-argocd
      tag = "0.9.0@sha256:dffc6c719d8635be2d5f2c8ad1c0178540325da4b40da0b373307e12b4c48f86";
    in
    {
      applications.argocd = {
        imports = [ (cluster.methods.mcp.mkAuth { ${name} = { inherit hostname port; }; }) ];

        resources = {
          configMaps.argocd-cm.data."accounts.${account}" = "apiKey";

          # MCP_READ_ONLY would also drop sync_application, so RBAC is the limit: the server
          # still lists create/update/delete_application and run_resource_action, and ArgoCD
          # refuses them.
          configMaps.argocd-rbac-cm.data."policy.${account}.csv" = ''
            g, ${account}, role:readonly
            p, ${account}, applications, sync, */*, allow
          '';

          ciliumNetworkPolicies = with cluster.methods.netpol; {
            ${name} = mkPolicy labels {
              ingress = [ (gatewayIngress port) ];
              # The only egress: a caller-supplied x-argocd-base-url can't carry the token anywhere else.
              egress = [ (toPods { "app.kubernetes.io/name" = "argocd-server"; } [ 8080 ]) ];
            };
            argocd-server.spec.ingress = [ (fromPods labels [ 8080 ]) ];
          };

          # No earlier sync-wave: the token only exists after the argocd stack is applied,
          # which needs accounts.mcp (above) synced first.
          externalSecrets.${name}.spec = {
            secretStoreRef = {
              name = "onepassword";
              kind = "ClusterSecretStore";
            };
            target.name = name;
            data = [
              {
                secretKey = "ARGOCD_API_TOKEN";
                remoteRef.key = "argocd/secrets/mcp-api-token";
              }
            ];
          };

          deployments.${name}.spec = {
            replicas = 1;
            selector.matchLabels = labels;
            template = {
              metadata.labels = labels;
              spec = {
                automountServiceAccountToken = false;
                securityContext = {
                  runAsNonRoot = true;
                  runAsUser = appId;
                  runAsGroup = appId;
                  seccompProfile.type = "RuntimeDefault";
                };
                volumes.cluster-ca.configMap.name = "cluster-ca";
                containers.${name} = {
                  image = "ghcr.io/argoproj-labs/mcp-for-argocd:${tag}";
                  # Envoy's JWT check is the inbound auth.
                  args = [
                    "http"
                    "--bind-address"
                    "0.0.0.0"
                    "--allow-unauthenticated"
                    "--allowed-host-header"
                    hostname
                  ];
                  env = {
                    ARGOCD_BASE_URL.value = "https://argocd-server.argocd.svc.cluster.local";
                    ARGOCD_API_TOKEN.valueFrom.secretKeyRef = {
                      inherit name;
                      key = "ARGOCD_API_TOKEN";
                    };
                    # argocd-server's cert is off the cluster CA (argocd/default.nix).
                    NODE_EXTRA_CA_CERTS.value = "/etc/cluster-ca/ca.crt";
                  };
                  volumeMounts."/etc/cluster-ca" = {
                    name = "cluster-ca";
                    readOnly = true;
                  };
                  ports.http.containerPort = port;
                  livenessProbe.httpGet = {
                    path = "/healthz";
                    port = "http";
                  };
                  readinessProbe.httpGet = {
                    path = "/healthz";
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
                      memory = "64Mi";
                    };
                    limits.memory = "256Mi";
                  };
                };
              };
            };
          };

          services.${name}.spec = {
            selector = labels;
            ports.http = {
              inherit port;
              targetPort = "http";
            };
          };
        };
      };
    };
}
