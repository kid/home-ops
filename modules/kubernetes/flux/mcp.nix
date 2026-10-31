# The Flux Operator MCP server, at /mcp on the Flux web UI's host behind
# cluster.methods.mcp's Kanidm JWT check (kanidm/mcp-auth.nix). Read-only,
# with read-only RBAC: the chart's own binds cluster-admin.
_: {
  den.aspects.kubernetes.flux-mcp.k8s-manifests =
    { charts, cluster, ... }:
    let
      name = "flux-operator-mcp";
      port = 9090;
    in
    {
      applications.${name} = {
        namespace = "flux-system";
        imports = [
          (cluster.methods.mcp.mkAuth {
            ${name} = {
              hostname = cluster.methods.mkAppHostname "flux";
              inherit port;
            };
          })
        ];

        helm.releases.${name} = {
          chart = charts.controlplaneio-fluxcd.flux-operator-mcp;
          values = {
            readonly = true;
            # The CiliumNetworkPolicy below replaces it.
            networkPolicy.create = false;
            rbac.create = false;
            resources = {
              requests = {
                cpu = "10m";
                memory = "64Mi";
              };
              limits.memory = "256Mi";
            };
          };
        };

        # flux-operator's chart role: get, list and watch on everything. Secret values stay masked.
        resources.clusterRoleBindings.${name} = {
          roleRef = {
            apiGroup = "rbac.authorization.k8s.io";
            kind = "ClusterRole";
            name = "flux-web-user";
          };
          subjects = [
            {
              kind = "ServiceAccount";
              inherit name;
              namespace = "flux-system";
            }
          ];
        };

        resources.ciliumNetworkPolicies = with cluster.methods.netpol; {
          ${name} = mkPolicy { "app.kubernetes.io/name" = name; } {
            ingress = [ (gatewayIngress port) ];
            egress = [ apiserverEgress ];
          };
        };
      };
    };
}
