# Prowlarr, the indexer manager the *arr apps search through, moved from
# pve1's CT 110, whose config was imported once into the kopiur-backed volume.
_:
let
  # renovate: datasource=docker depName=ghcr.io/home-operations/prowlarr
  tag = "3.0.1.5752@sha256:83cc967a3b7b754634e31773d4d58ea606714490b7e8592d41b608f7c249afe6";
in
{
  den.aspects.kubernetes.media.prowlarr.k8s-manifests =
    { cluster, ... }:
    {
      applications.prowlarr = cluster.methods.mkMediaApp {
        name = "prowlarr";
        inherit tag;
        port = 9696;
        # The image runs as any uid.
        uid = 1000;
        replicas = 1;
      };
    };
}
