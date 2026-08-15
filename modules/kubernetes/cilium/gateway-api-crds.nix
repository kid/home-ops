# Upstream gateway-api standard-channel CRDs — Cilium's chart doesn't
# install them, and gatewayAPI.enabled (cilium/default.nix) silently no-ops
# without them. Own applications.gateway-api-crds entry, not folded into
# applications.cilium, so bumping this doesn't couple to the Cilium chart.
# v1.4.1 matches what Cilium 1.19.6 (charts.cilium.cilium) requires. `config/crd`, not `config/crd/standard`: the latter has no
# kustomization.yaml of its own.
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
        path = "config/crd";
      };
    };
}
