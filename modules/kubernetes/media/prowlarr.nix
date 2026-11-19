# Prowlarr, the indexer manager the *arr apps search through, moved from
# pve1's CT 110, whose config was imported once into the kopiur-backed volume.
_:
let
  # renovate: datasource=docker depName=ghcr.io/home-operations/prowlarr
  tag = "3.0.2.5780@sha256:58fa5dbed20738ce0a72077315e818eeb731cb4b4a5173c4a837d343a9573750";
in
{
  den.aspects.kubernetes.media.prowlarr.k8s-manifests =
    { cluster, ... }:
    cluster.methods.mkMediaApp {
      name = "prowlarr";
      inherit tag;
      port = 9696;
      # The image runs as any uid.
      uid = 1000;
    };
}
