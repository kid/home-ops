# Prowlarr, the indexer manager the *arr apps search through, moved from
# pve1's CT 110, whose config was imported once into the kopiur-backed volume.
_:
let
  # renovate: datasource=docker depName=ghcr.io/home-operations/prowlarr
  tag = "3.0.0.5737@sha256:0954599432e16ccd86129f1eb8eb0247fd0d1591aab400f73e2010a1cda37be8";
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
