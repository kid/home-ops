# sops-operator (peak-scale/sops-operator): SopsSecret manifests are
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
# SopsProvider isn't a core Kubernetes type, so nixidy has no built-in typed
# option for it — generators.fromChartCRDModule (the same technique
# cert-manager/external-secrets use) generates it live from the chart's own
# CRD. SopsSecret is deliberately *not* typed this way — see
# modules/kubernetes/_secrets-lib.nix's header for why (its CRD schema
# requires a `sops` block that only exists after encryption).
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
          kindFilter = [ "SopsProvider" ];
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
            # --filename-override: sops picks a .sops.yaml creation_rule by
            # matching path_regex against a real file path. Piping through
            # /dev/stdin gives it none, so without this it silently falls
            # through to the humans-only catch-all rule instead of the
            # cluster-scoped one (modules/flake/sops-config.nix's
            # clusterManifestsRule) — confirmed by inspecting a real
            # encrypted output file, which had exactly that: no cluster key.
            command =
              _:
              ''sops --encrypt --input-type yaml --output-type yaml --filename-override "$TARGET_PATH" /dev/stdin'';
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
