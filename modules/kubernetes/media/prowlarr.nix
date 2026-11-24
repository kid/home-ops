# Prowlarr, the indexer manager the *arr apps search through, moved from
# pve1's CT 110, whose config was imported once into the kopiur-backed volume.
_:
let
  # renovate: datasource=docker depName=ghcr.io/home-operations/prowlarr
  tag = "3.1.0.5799@sha256:15b68a6e69f893a3ede6fed405594d3f5d9e9d13648246a0fefbafe4fd7f595b";
in
{
  den.aspects.kubernetes.media.prowlarr.generated-secrets = { cluster, ... }: [
    (cluster.methods.mkMediaApiKey "prowlarr")
  ];

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
