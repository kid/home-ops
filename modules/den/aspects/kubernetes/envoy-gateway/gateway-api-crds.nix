# Typed nixidy options for Gateway API resources (GatewayClass, Gateway,
# HTTPRoute, GRPCRoute, BackendTLSPolicy, TLSRoute, ReferenceGrant) — this aspect produces
# types only, no CRD manifests. The real CRDs are installed by Envoy
# Gateway's own chart (envoy-gateway/default.nix's crds.enabled = true),
# which bundles its own copy of the Gateway API CRDs, so the types are
# read from that same already-vendored chart instead of a second,
# independent upstream pin. CRD version bumps ride along with the
# envoyproxy/gateway-helm chart bump (charts/ + helmupdater), not a
# separate Renovate PR.
_: {
  den.aspects.kubernetes.gateway-api-crds.k8s-manifests =
    { charts, generators, ... }:
    {
      nixidy.applicationImports = [
        (generators.fromCRDModule {
          name = "gateway-api";
          src = charts.envoyproxy.gateway-helm;
          crdFiles = [ "charts/crds/crds/gatewayapi-crds.yaml" ];
          kindFilter = [
            "Gateway"
            "HTTPRoute"
            "GRPCRoute"
            "BackendTLSPolicy"
            "GatewayClass"
            "TLSRoute"
            "ReferenceGrant"
          ];
        })
      ];
    };
}
