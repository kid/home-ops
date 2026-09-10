# Envoy Gateway (https://gateway.envoyproxy.io/), replacing Cilium's own
# Gateway API controller (see cilium/default.nix's envoy.enabled = false).
# apps-gateway/default.nix's Gateway references this GatewayClass by name.
_: {
  den.aspects.kubernetes.envoy-gateway.k8s-manifests =
    { charts, ... }:
    {
      applications.envoy-gateway = {
        namespace = "envoy-gateway-system";
        createNamespace = true;

        helm.releases.envoy-gateway = {
          chart = charts.envoyproxy.gateway-helm;
          values = {
            # Gateway API CRDs are installed separately (gateway-api-crds.nix,
            # upstream standard channel) — the chart's own bundled copy
            # defaults to the experimental channel and would conflict.
            crds.enabled = false;
          };
        };

        # The chart doesn't create a GatewayClass itself (unlike Cilium's
        # gatewayClass.create shortcut) — gatewayclasses isn't one of
        # gateway-api-crds.nix's typed nixidy imports, so this goes through
        # the same raw-YAML escape hatch sops-operator's mkSopsSecret uses.
        yamls = [
          (builtins.toJSON {
            apiVersion = "gateway.networking.k8s.io/v1";
            kind = "GatewayClass";
            metadata.name = "envoy";
            spec.controllerName = "gateway.envoyproxy.io/gatewayclass-controller";
          })
        ];
      };
    };
}
