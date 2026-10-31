# Flux, installed and upgraded by the Flux Operator
# (https://fluxoperator.dev). The operator runs from its Helm chart; the
# FluxInstance below makes it deploy the Flux controllers and the root sync:
# a GitRepository plus a Kustomization named flux-system that applies
# manifests/<cluster>/apps, where nixidy-defaults.nix renders one Flux
# Kustomization per app. modules/den/aspects/services/k3s/bootstrap.nix
# applies this app once on a new cluster; from then on Flux manages it too.
#
# The operator also serves the Flux web UI. Envoy Gateway's OIDC
# (cluster.methods.mkOidcAuth) lets only Kanidm's admins reach it, so the UI
# runs Anonymous: every request acts as the flux-web-admins group.
_: {
  den.aspects.kubernetes.flux.k8s-manifests =
    {
      charts,
      generators,
      cluster,
      config,
      ...
    }:
    let
      webPort = 9080;
      webGroup = "flux-web-admins";
      hostname = cluster.methods.mkAppHostname "flux";
    in
    {
      nixidy.applicationImports = [
        (generators.fromChartCRDModule {
          name = "flux-operator";
          chart = charts.controlplaneio-fluxcd.flux-operator;
          kindFilter = [ "FluxInstance" ];
        })
      ];

      applications.flux-operator = {
        namespace = "flux-system";

        resources.ciliumNetworkPolicies =
          with cluster.methods.netpol;
          let
            controller = name: { app = name; };
          in
          {
            flux-operator = mkPolicy { "app.kubernetes.io/name" = "flux-operator"; } {
              ingress = [ (gatewayIngress webPort) ];
              egress = [ apiserverEgress ];
            };
            source-controller = mkPolicy (controller "source-controller") {
              # Artifact downloads.
              ingress = [ (fromPods (controller "kustomize-controller") [ 9090 ]) ];
              egress = [
                apiserverEgress
                (fqdnEgress [ "github.com" ] [ 443 ])
              ];
            };
            kustomize-controller = mkPolicy (controller "kustomize-controller") {
              egress = [
                apiserverEgress
                (toPods (controller "source-controller") [ 9090 ])
              ];
            };
          };

        helm.releases.flux-operator = {
          chart = charts.controlplaneio-fluxcd.flux-operator;
          values = {
            web = {
              # The CiliumNetworkPolicy above replaces it.
              networkPolicy.create = false;
              config.authentication = {
                type = "Anonymous";
                anonymous.groups = [ webGroup ];
              };
              # No metrics-server here: collection only logs errors.
              config.metrics.disabled = true;
            };
            resources = {
              requests = {
                cpu = "10m";
                memory = "64Mi";
              };
              # Peaked at 172Mi without the web UI.
              limits.memory = "512Mi";
            };
          };
        };

        resources.fluxInstances.flux.spec = {
          # The manifests come from the operator image, so the chart pin picks the Flux version.
          distribution = {
            version = "2.x";
            registry = "ghcr.io/fluxcd";
          };
          components = [
            "source-controller"
            "kustomize-controller"
          ];
          cluster = {
            type = "kubernetes";
            size = "small";
            # Upstream's NetworkPolicies would widen the CiliumNetworkPolicies above.
            networkPolicy = false;
          };
          sync = with config.nixidy.target; {
            kind = "GitRepository";
            url = repository;
            ref = "refs/heads/${branch}";
            path = "${rootPath}/${config.nixidy.appOfApps.name}";
          };
        };
      };

      # Separate from flux-operator so the operator never waits on Kanidm.
      applications.flux-web = {
        namespace = "flux-system";
        imports = [
          (cluster.methods.mkOidcAuth {
            name = "flux-web";
            httpRouteName = "flux-web";
            inherit hostname;
            group = "admins";
          })
        ];

        # The chart's role: read everything, and the UI's actions on Flux objects and workloads.
        resources.clusterRoleBindings.${webGroup} = {
          roleRef = {
            apiGroup = "rbac.authorization.k8s.io";
            kind = "ClusterRole";
            name = "flux-web-admin";
          };
          subjects = [
            {
              apiGroup = "rbac.authorization.k8s.io";
              kind = "Group";
              name = webGroup;
            }
          ];
        };

        resources.httpRoutes.flux-web.spec = {
          parentRefs = [
            {
              group = "gateway.networking.k8s.io";
              kind = "Gateway";
              name = "apps";
              namespace = "envoy-gateway-system";
              sectionName = "https";
            }
          ];
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
                  name = "flux-operator";
                  port = webPort;
                  weight = 1;
                }
              ];
            }
          ];
        };
      };
    };
}
