# Upstream gateway-api standard-channel CRDs — Cilium's chart doesn't
# install them, and gatewayAPI.enabled (cilium/default.nix) silently no-ops
# without them. Own applications.gateway-api-crds entry, not folded into
# applications.cilium, so bumping this doesn't couple to the Cilium chart.
# v1.4.1 matches what Cilium 1.19.6 (nixhelm's charts.cilium.cilium)
# requires. `config/crd`, not `config/crd/standard`: the latter has no
# kustomization.yaml of its own.
_: {
  den.aspects.gateway-api-crds.k8s-manifests =
    { pkgs, ... }:
    {
      applications.gateway-api-crds.kustomize.applications.gateway-api-crds.kustomization = {
        src = pkgs.fetchFromGitHub {
          owner = "kubernetes-sigs";
          repo = "gateway-api";
          rev = "v1.4.1";
          hash = "sha256-/GHyikcC2QGDN0ndpY6/xvSEEnpSsLrNU+lFElCKBs8=";
        };
        path = "config/crd";
      };
    };
}
