# sops-operator (peak-scale/sops-operator), an alternative to the
# ESO+1Password (external-secrets-1password branch) and ESO+OpenBao
# (external-secrets-openbao branch) designs: SopsSecret manifests are
# committed to git as real ciphertext (encrypted at `nixidy switch` time via
# the objectTransforms postProcess rule below), and this operator decrypts
# them in-cluster using the cluster's own sops-age key (modules/flake/
# provision-cluster-key.nix, seeded into the cluster by modules/den/aspects/
# services/k3s/sops-operator.nix).
#
# Chart isn't in nixhelm's catalog — fetched directly from the upstream repo
# (a real Helm chart lives at charts/sops-operator/ in-repo there) at a
# pinned tag, same fetchFromGitHub-for-a-non-cataloged-source pattern
# modules/kubernetes/argocd/default.nix already uses for a kustomize base.
#
# SopsProvider/SopsSecret aren't core Kubernetes types, so nixidy has no
# built-in typed options for them — generators.fromChartCRDModule (the same
# technique cert-manager/external-secrets use) generates them live from the
# chart's own CRDs.
_: {
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
          kindFilter = [
            "SopsProvider"
            "SopsSecret"
          ];
        })
      ];

      # Environment-wide (not applications.sops-operator-scoped), since any
      # app aspect can declare its own SopsSecret and needs the same
      # encryption applied. postProcess only runs via the real `nixidy
      # switch`/`nixidy apply` CLI (modules/flake/files.nix), never inside a
      # sandboxed Nix build — it needs real `sops` + the committed
      # .sops.yaml's public recipients, neither available in a build sandbox.
      nixidy.objectTransforms = [
        {
          name = "encrypt-sops-secrets";
          match.kind = "SopsSecret";
          postProcess = {
            runtimeInputs = [ pkgs.sops ];
            command = _: "sops --encrypt --input-type yaml --output-type yaml /dev/stdin";
          };
        }
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
