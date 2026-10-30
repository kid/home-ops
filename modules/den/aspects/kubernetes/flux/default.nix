# Flux, installed and upgraded by the Flux Operator
# (https://fluxoperator.dev). The operator runs from its Helm chart; the
# FluxInstance below makes it deploy the Flux controllers and the root sync:
# a GitRepository plus a Kustomization named flux-system that applies
# manifests/<cluster>/apps, where nixidy-defaults.nix renders one Flux
# Kustomization per app. modules/den/aspects/services/k3s/bootstrap.nix
# applies this app once on a new cluster; from then on Flux manages it too.
_: {
  den.aspects.kubernetes.flux.k8s-manifests =
    {
      charts,
      generators,
      cluster,
      config,
      ...
    }:
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
            # Its OIDC login needs the client secret inside a config file, which
            # nothing here can render from kaniop's credentials Secret yet.
            web.enabled = false;
            resources = {
              requests = {
                cpu = "10m";
                memory = "64Mi";
              };
              limits.memory = "256Mi";
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
    };
}
