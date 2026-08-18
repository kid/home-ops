# sops-operator (peak-scale/sops-operator): SopsSecret manifests are
# committed to git as real ciphertext (encrypted by `nix run .#write-manifests`,
# modules/flake/files.nix, after it merges in each secret's real value from
# a committed file under secrets/ — see den.clusters.prd.methods.mkSopsSecret
# below), and this operator decrypts them in-cluster using the cluster's own
# sops-age key (modules/flake/provision-cluster-key.nix, seeded into the
# cluster by modules/den/aspects/services/k3s/sops-operator.nix).
#
# Chart isn't in nixhelm's catalog — fetched directly from the upstream repo
# (a real Helm chart lives at charts/sops-operator/ in-repo there) at a
# pinned tag, same fetchFromGitHub-for-a-non-cataloged-source pattern
# modules/kubernetes/argocd/default.nix already uses for a kustomize base.
#
# SopsProvider isn't a core Kubernetes type, so nixidy has no built-in typed
# option for it — generators.fromChartCRDModule (the same technique
# cert-manager/external-secrets use) generates it live from the chart's own
# CRD. SopsSecret is deliberately *not* typed this way, and can't be:
# confirmed by trying it (adding "SopsSecret" to kindFilter below breaks the
# whole environment build, even with zero resources.sopsSecrets instances
# declared) — the CRD's `sops` block requires `lastmodified`/`mac` with no
# default, and nixidy's own schema-walk forces evaluation of every declared
# kind's defaults regardless of usage. nixidy's own docs independently steer
# away from typed resources for sops-encrypted manifests anyway
# (`extraRawYamls`/raw YAML, since round-tripping ciphertext through
# kube.fromYAML/toYAML can reformat ENC[...] values and breaks decryption).
# den.clusters.prd.methods.mkSopsSecret (set below) builds the pre-encryption
# shape as YAML text instead, consumed via the same applications.<name>.yamls
# raw escape hatch modules/kubernetes/cilium/bgp.nix already uses.
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
