# Pinned Helm charts

Each `charts/<org>/<chart>/default.nix` pins one Helm chart directly in
this repo — `{ repo; chart; version; chartHash; }` — instead of relying on
nixhelm's own chart index. `modules/flake/charts.nix` loads this directory
tree and fetches each entry into a chart derivation, exposed as
`chartsDerivations.<system>.<org>.<chart>` and consumed by
`modules/kubernetes/*/default.nix` as `charts.<org>.<chart>`.

Add or update a pin with nixhelm's `helmupdater` CLI, available in the
devshell:

```console
helmupdater init "<repo-url>" "<org>/<chart-name>"   # add a new pin
helmupdater update "<org>/<chart-name>"              # bump one pin's version + hash
helmupdater update-all                               # bump every pin
helmupdater rehash "<org>/<chart-name>"               # recompute hash only
```

After bumping, run `nix run .#write-manifests` and commit both the
`charts/` change and the regenerated `manifests/prd/` output together —
`checks.manifests` fails otherwise. Renovate does this on its own: its
self-hosted run (`.github/workflows/renovate.yaml`) bumps each pin's
`version`, then `postUpgradeTasks` (`.renovaterc.json5`) runs
`refresh-nix-hash` (which calls `helmupdater rehash`) and `write-manifests`,
and opens a PR with the changelog.
