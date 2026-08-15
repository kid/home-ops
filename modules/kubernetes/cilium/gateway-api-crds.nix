# Upstream gateway-api standard-channel CRDs — Cilium's chart doesn't
# install them, and gatewayAPI.enabled (cilium/default.nix) silently no-ops
# without them. Own applications.gateway-api-crds entry, not folded into
# applications.cilium, so bumping this doesn't couple to the Cilium chart.
#
# v1.6.1, not the older v1.4.1: Cilium 1.19.6's operator unconditionally
# sets up a controller-runtime field indexer for TLSRoute whenever
# gatewayAPI.enabled is true, even though it lists TLSRoute as merely
# "optional" in its own resource-availability check — so it hard-crashes
# at startup ("no matches for kind \"TLSRoute\" in version
# \"gateway.networking.k8s.io/v1alpha2\"") without it, and v1.4.1's
# TLSRoute only exists in the experimental channel. gateway-api promoted
# TLSRoute (along with TCPRoute/UDPRoute) to the standard channel at v1
# in a later release — v1.6.1 has it, matching the "v1" storage version
# k3s's own bundled traefik-crd Helm release already stamped into this
# cluster's TLSRoute CRD (installed despite --disable=traefik, which only
# disables the traefik deployment, not its CRD-only chart) — so `config/
# crd` (standard) is enough again, no need for the broader `experimental`
# channel this time.
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
          rev = "v1.6.1";
          hash = "sha256-Hq3vaCQRSRFjya76qRYw4/BcH00Wu5wE6UQACrjKJSk=";
        };
        path = "config/crd";
      };
    };
}
