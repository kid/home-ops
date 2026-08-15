# Upstream gateway-api CRDs — Cilium's chart doesn't install them, and
# gatewayAPI.enabled (cilium/default.nix) silently no-ops without them.
# Own applications.gateway-api-crds entry, not folded into
# applications.cilium, so bumping this doesn't couple to the Cilium chart.
#
# config/crd/experimental, not config/crd (the standard channel): Cilium
# 1.19.6's operator unconditionally sets up a controller-runtime field
# indexer for TLSRoute whenever gatewayAPI.enabled is true, even though it
# lists TLSRoute as merely "optional" in its own resource-availability
# check — so it hard-crashes at startup ("no matches for kind \"TLSRoute\"
# in version \"gateway.networking.k8s.io/v1alpha2\"") without it, standard
# channel alone isn't enough. experimental is a superset of standard (see
# its own kustomization.yaml), not an add-on to it.
#
# The Renovate annotation below tracks this independently of Cilium's own
# version — check the Cilium release notes for its required Gateway API
# CRD version before merging a bump here, don't take it on trust.
_: {
  den.aspects.gateway-api-crds.k8s-manifests =
    { pkgs, ... }:
    {
      applications.gateway-api-crds.kustomize.applications.gateway-api-crds.kustomization = {
        src = pkgs.fetchFromGitHub {
          owner = "kubernetes-sigs";
          repo = "gateway-api";
          # renovate: datasource=github-releases depName=kubernetes-sigs/gateway-api
          rev = "v1.4.1";
          hash = "sha256-/GHyikcC2QGDN0ndpY6/xvSEEnpSsLrNU+lFElCKBs8=";
        };
        path = "config/crd/experimental";
      };
    };
}
