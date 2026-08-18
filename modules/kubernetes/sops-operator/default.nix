# sops-operator (peak-scale/sops-operator). Chart isn't in nixhelm's
# catalog, fetched directly at a pinned tag.
#
# SopsSecret can't use fromChartCRDModule like SopsProvider below does:
# its CRD's required sops.lastmodified/mac (no default) break the whole
# build via nixidy's schema-walk, even with zero instances declared.
_: {
  den.clusters.prd.methods.mkSopsSecret =
    { namespace, name }:
    builtins.toJSON {
      apiVersion = "addons.projectcapsule.dev/v1alpha1";
      kind = "SopsSecret";
      metadata = { inherit name namespace; };
      spec.secrets = [
        {
          inherit name;
          stringData = { };
        }
      ];
    };

  den.aspects.sops-operator.k8s-manifests =
    { pkgs, generators, ... }:
    let
      chartSrc = pkgs.fetchFromGitHub {
        owner = "peak-scale";
        repo = "sops-operator";
        rev = "v0.10.1";
        hash = "sha256-iQQMRVfqn7f8rf7l+q7tWR5t7NH/JfPw9q8m0kfsmu4=";
      };
      chart = chartSrc + "/charts/sops-operator";
    in
    {
      nixidy.applicationImports = [
        (generators.fromChartCRDModule {
          name = "sops-operator";
          inherit chart;
          kindFilter = [ "SopsProvider" ];
        })
      ];

      applications.sops-operator = {
        namespace = "sops-operator";
        createNamespace = true;

        helm.releases.sops-operator = {
          inherit chart;
          values = {
            crds.install = true;
          };
        };

        # Cluster-scoped: matches every labeled key Secret and every
        # SopsSecret cluster-wide — no Capsule/tenant scoping needed for a
        # single-tenant homelab cluster. Matches the "empty matchLabels ==
        # no restriction" shape from the operator's own docs.
        resources.sopsProviders.prd.spec = {
          keys = [ { matchLabels = { }; } ];
          sops = [ { matchLabels = { }; } ];
        };
      };
    };
}
