# AGENTS

- Enter the repo through `direnv`/the flake shell. `.envrc` sets repo-local `TALOSCONFIG=$(pwd)/talosconfig` and `KUBECONFIG=$(pwd)/kubeconfig`; do not assume global kube or Talos config.
- Formatting is defined by `flake.nix` via treefmt. Relevant formatters here are `terraform` for `*.tofu`, `yamlfmt`, and `nixfmt`. `*.sops.*` files are excluded from formatting.

## Repo Shape

- `tf-stacks/`: Terragrunt environment and stack wiring. Shared inputs, secrets loading, and remote state are centralized in `tf-stacks/root.hcl`.
- `clusters/dev/`: cluster bootstrap entrypoint. `clusters/dev/kustomization.yaml` applies `./flux` and generates `cluster-values` from `clusters/dev/cluster.env`.
- `clusters/dev/apps/kustomization.yaml`: the real app-selection overlay for the dev cluster.
- `kubernetes/apps/`: app manifests and Flux `Kustomization`/`HelmRelease` definitions.
- `kubernetes/components/`: shared components used by apps, including `cluster-values`.
- `test/`: Go/Terratest integration checks for RouterOS/network behavior, not generic unit tests.

## Flux And Kubernetes

- Do not edit `kubernetes/apps/kustomization.yaml` to add apps for the dev cluster. It is intentionally empty; cluster composition happens in `clusters/dev/apps/kustomization.yaml`.
- `clusters/dev/flux/ks.apps.yaml` injects `postBuild.substituteFrom` for `ConfigMap/cluster-values` and optional `Secret/namespace-secrets` into most Flux `Kustomization` objects. Do not duplicate that wiring unless you need to opt out.
- Preserve `${...}` placeholders in manifests. Many values are resolved by Flux post-build substitution from `clusters/dev/cluster.env`, not by shell expansion.
- Preserve Flux ordering fields such as `dependsOn`, `wait`, and namespaces. Bootstrap in `dagger/bootstrap/main.go` relies on a minimal ordered subset of apps before full reconciliation.
- Use `clusters/dev/cluster.env` as the source of truth for cluster-wide values like domains, CIDRs, and storage class names.

## PR Deployment

- For temporary live testing, suspend only `Kustomization/flux-system`. Do not suspend the `GitRepository`; `flux-system` is the object that would otherwise reconcile the source configuration back to the normal branch.
- When working from a branch, always open a PR for it before live testing.
- Before deploying a PR, check whether `GitRepository/flux-system` is already pinned to another PR merge ref. Do not replace an active PR deployment without explicit user approval.
- Patch live `GitRepository/flux-system` to the PR merge ref `refs/pull/<id>/merge`, then let the webhook or a manual reconcile of `GitRepository/flux-system` fetch the new source artifact while `flux-system` remains suspended.
- Reconcile the owning app `Kustomization` to apply changed git-managed manifests from the fetched branch. Reconcile a `HelmRelease` only when you need to re-run Helm after the `HelmRelease` spec has already been applied.
- Do not resume `flux-system` while the cluster should stay on the PR merge ref; resuming it will allow Flux to restore the normal source branch.
- For rollback or cleanup, prefer waiting until the PR is merged so the normal branch contains the tested changes before switching the cluster back.
- After merge, resuming `Kustomization/flux-system` should be sufficient; it will reconcile the source configuration back to the normal branch.

## Talos

- The dev cluster in `clusters/dev/talos/config.yaml` is three control-plane nodes; there are no dedicated workers.
- `clusters/dev/talos/patches/schedule-on-controlplane.yaml` enables scheduling on control planes. Do not assume workloads must avoid them.
- `clusters/dev/talos/patches/cilium.yaml` sets Talos CNI to `none`; cluster networking is expected to come later from Kubernetes manifests.

## Terragrunt

- Start from `tf-stacks/root.hcl` when changing stack behavior. It loads SOPS secrets, derives per-environment/per-device inputs, and configures Cloudflare R2 remote state.
- Stack dependency order is encoded in the checked-in `terragrunt.hcl` files. Read dependencies before changing related stacks.
- `tf-stacks/dev/lab/terragrunt.hcl` intentionally points at `secrets/prd/routeros.sops.yaml`. Do not “fix” that without confirming the workflow.

## Verification

- For cluster manifest changes, run the Flux-local checks through Dagger as exposed by `dagger.json` and implemented in `dagger/flux-local/main.go`. Use `direnv exec . dagger call flux-local test` to run the repo's cluster test suite and `direnv exec . dagger call flux-local test-build` to run the repo's cluster build suite. For single-cluster or targeted rendering, use `direnv exec . dagger call flux-local build --path clusters/<cluster> --kind all export --path /tmp/<cluster>.yaml`.
- Do not run blind `envsubst` over rendered manifests. `dagger/bootstrap/main.go` explicitly avoids that because Helm/manifests may contain placeholders that must survive rendering.
- `test/network_management_test.go` requires SOPS-decryptable `secrets/dev/routeros.sops.yaml` and reachable RouterOS OOB IPs; it is an environment-dependent integration test.
