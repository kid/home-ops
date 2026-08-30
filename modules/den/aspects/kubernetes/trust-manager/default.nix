# Syncs hubble-ca-secret into a ConfigMap so BackendTLSPolicy can read it
# (it can't read Secrets). Not in nixhelm's catalog, so fetched directly.
_: {
  den.aspects.kubernetes.trust-manager.k8s-manifests =
    { pkgs, generators, ... }:
    let
      chartSrc = pkgs.fetchFromGitHub {
        owner = "cert-manager";
        repo = "trust-manager";
        # renovate: datasource=github-releases depName=cert-manager/trust-manager
        rev = "v0.24.0";
        hash = "sha256-4ek0g9zoMB0TDod5iSvEc5f/KPQk3FxVkduECTWvkds=";
      };
      chart = chartSrc + "/deploy/charts/trust-manager";
    in
    {
      nixidy.applicationImports = [
        (generators.fromChartCRDModule {
          name = "trust-manager";
          inherit chart;
          kindFilter = [ "Bundle" ];
          extraOpts = [
            "--set"
            "crds.enabled=true"
          ];
        })
      ];

      applications.trust-manager = {
        namespace = "cert-manager";

        helm.releases.trust-manager = {
          inherit chart;
          values.crds.enabled = true;
        };

        resources.bundles.internal-ca.spec = {
          sources = [
            {
              secret = {
                name = "hubble-ca-secret";
                key = "ca.crt";
              };
            }
          ];
          target = {
            configMap.key = "ca.crt";
            namespaceSelector.matchLabels."kubernetes.io/metadata.name" = "argocd";
          };
        };
      };
    };
}
