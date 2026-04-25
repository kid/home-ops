# VictoriaMetrics Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `kube-prometheus-stack` with `victoria-metrics-k8s-stack`, keep Prometheus Operator CRDs as the repo contract, move custom rules to a dedicated Flux app, and update Grafana provisioning for the renamed datasource.

**Architecture:** Add a new `victoria-metrics` Flux app for the Helm chart and a `victoria-metrics-rules` Flux app for repo-managed `PrometheusRule` manifests. Keep Grafana external to the chart, enable cert-manager-backed webhooks, depend on storage before PVC creation, and update repo-managed dashboards to the new metrics datasource name.

**Tech Stack:** Flux Kustomizations, HelmRelease/OCIRepository, VictoriaMetrics K8s Stack, Prometheus Operator CRDs, Grafana Operator resources, `flux-local`

---

### Task 1: Add the VictoriaMetrics Flux apps

**Files:**
- Create: `kubernetes/apps/observability/victoria-metrics/ks.app.yaml`
- Create: `kubernetes/apps/observability/victoria-metrics/app/kustomization.yaml`
- Create: `kubernetes/apps/observability/victoria-metrics/app/ocirepository.yaml`
- Create: `kubernetes/apps/observability/victoria-metrics/app/helmrelease.yaml`
- Create: `kubernetes/apps/observability/victoria-metrics-rules/ks.app.yaml`
- Create: `kubernetes/apps/observability/victoria-metrics-rules/app/kustomization.yaml`
- Modify: `kubernetes/apps/observability/kustomization.yaml`

- [ ] **Step 1: Write the failing verification target**

Document the expected new observability app paths in the plan and verify they do not exist yet with:

```bash
test -e kubernetes/apps/observability/victoria-metrics/ks.app.yaml
```

Expected: command exits non-zero because the new app has not been created.

- [ ] **Step 2: Run the failing verification**

Run:

```bash
test -e kubernetes/apps/observability/victoria-metrics/ks.app.yaml
```

Expected: exit code `1`.

- [ ] **Step 3: Write the new Flux app manifests**

Create the new app skeletons following the existing observability patterns:

- `victoria-metrics/ks.app.yaml` depends on `cert-manager` in `network-system` and the storage Kustomization that owns `linstor-zfs-ssd`
- `victoria-metrics-rules/ks.app.yaml` depends on `victoria-metrics`
- the observability kustomization includes both new apps and stops including `kube-prometheus-stack`

- [ ] **Step 4: Run targeted verification**

Run:

```bash
flux-local build all --skip-invalid-kustomization-paths --enable-helm clusters/dev
```

Expected: render succeeds and includes `victoria-metrics` and `victoria-metrics-rules` Kustomizations.

### Task 2: Configure the VictoriaMetrics stack chart

**Files:**
- Modify: `kubernetes/apps/observability/victoria-metrics/app/helmrelease.yaml`

- [ ] **Step 1: Write the failing verification target**

Define the expected behaviors to render:

- bundled Grafana disabled
- cert-manager integration enabled
- persistent storage on `linstor-zfs-ssd`
- chart-managed `VMAlert`, `VMAlertmanager`, and kube-prometheus-derived defaults enabled

- [ ] **Step 2: Run the failing verification**

Run:

```bash
grep -n "linstor-zfs-ssd\|cert-manager\|grafana:\|enabled: false" kubernetes/apps/observability/victoria-metrics/app/helmrelease.yaml
```

Expected: file does not exist yet or does not contain the required configuration.

- [ ] **Step 3: Write the HelmRelease values**

Configure `victoria-metrics-k8s-stack` with:

- a stable release name / name override
- Grafana disabled
- Prometheus Operator object conversion left enabled
- cert-manager-backed webhook support enabled
- persistent `VMSingle` storage on `linstor-zfs-ssd`
- retention comparable to the current setup
- `VMAlertmanager` enabled but not externally routed
- default dashboards/rules enabled

- [ ] **Step 4: Run targeted verification**

Run:

```bash
flux-local test -A --enable-helm --path clusters/dev
```

Expected: Helm rendering succeeds for the new chart.

### Task 3: Move custom rules into repo-managed PrometheusRule manifests

**Files:**
- Create: `kubernetes/apps/observability/victoria-metrics-rules/app/dockerhub-rules.yaml`
- Create: `kubernetes/apps/observability/victoria-metrics-rules/app/oom-rules.yaml`
- Create: `kubernetes/apps/observability/victoria-metrics-rules/app/zfs-rules.yaml`

- [ ] **Step 1: Write the failing verification target**

Confirm the new rule files do not exist yet:

```bash
test -e kubernetes/apps/observability/victoria-metrics-rules/app/dockerhub-rules.yaml
```

Expected: exit code `1`.

- [ ] **Step 2: Run the failing verification**

Run:

```bash
test -e kubernetes/apps/observability/victoria-metrics-rules/app/dockerhub-rules.yaml
```

Expected: exit code `1`.

- [ ] **Step 3: Write the PrometheusRule manifests**

Convert the custom rules from the old Helm values into standalone `PrometheusRule` resources with explicit groups and rules.

- [ ] **Step 4: Run targeted verification**

Run:

```bash
flux-local build all --skip-invalid-kustomization-paths --enable-helm clusters/dev
```

Expected: rendered output includes the three new `PrometheusRule` resources.

### Task 4: Update Grafana datasource and dashboard resources

**Files:**
- Modify: `kubernetes/apps/observability/grafana/resources/datasource-prometheus.yaml`
- Modify: `kubernetes/apps/storage-system/volsync/app/grafana-dashboard.yaml`
- Modify: `kubernetes/apps/observability/mikrotik-exporter/app/grafana/dashboard.yaml`
- Modify: any other repo-managed `GrafanaDashboard` resources that reference the old datasource name

- [ ] **Step 1: Write the failing verification target**

Capture the current old datasource references:

```bash
rg "datasourceName: Prometheus|name: Prometheus" kubernetes/apps
```

Expected: at least the current datasource and dashboard resources reference `Prometheus`.

- [ ] **Step 2: Run the failing verification**

Run:

```bash
rg "datasourceName: Prometheus|name: Prometheus" kubernetes/apps
```

Expected: matches are found.

- [ ] **Step 3: Write the datasource/dashboard updates**

Rename the metrics datasource to the chosen VictoriaMetrics name, point it at the VictoriaMetrics query URL, and update repo-managed `GrafanaDashboard` resources to reference the new datasource name.

- [ ] **Step 4: Run targeted verification**

Run:

```bash
rg "datasourceName: Prometheus|name: Prometheus" kubernetes/apps
```

Expected: no remaining metrics-datasource references to `Prometheus` outside intentionally unrelated text.

### Task 5: Remove kube-prometheus-stack manifests and verify the migration

**Files:**
- Delete: `kubernetes/apps/observability/kube-prometheus-stack/ks.app.yaml`
- Delete: `kubernetes/apps/observability/kube-prometheus-stack/app/helmrelease.yaml`
- Delete: `kubernetes/apps/observability/kube-prometheus-stack/app/ocirepository.yaml`
- Delete: `kubernetes/apps/observability/kube-prometheus-stack/app/kustomization.yaml`
- Modify: `docs/superpowers/specs/2026-04-25-victoria-metrics-design.md` only if implementation realities require a documented adjustment

- [ ] **Step 1: Write the failing verification target**

Confirm the old app is still present before removal:

```bash
test -e kubernetes/apps/observability/kube-prometheus-stack/ks.app.yaml
```

Expected: exit code `0`.

- [ ] **Step 2: Run the baseline verification**

Run:

```bash
test -e kubernetes/apps/observability/kube-prometheus-stack/ks.app.yaml
```

Expected: exit code `0`.

- [ ] **Step 3: Remove the old manifests and run full verification**

Run all required repo verification commands:

```bash
flux-local test -A --enable-helm --path clusters/dev
flux-local build all --skip-invalid-kustomization-paths --enable-helm clusters/dev
```

Expected: both commands exit `0` and the rendered manifests no longer contain `kube-prometheus-stack`.

- [ ] **Step 4: Commit**

```bash
git add kubernetes/apps/observability kubernetes/apps/storage-system/volsync/app/grafana-dashboard.yaml kubernetes/apps/observability/mikrotik-exporter/app/grafana/dashboard.yaml docs/superpowers/specs/2026-04-25-victoria-metrics-design.md docs/superpowers/plans/2026-04-25-victoria-metrics-migration.md
git commit -m "feat: migrate observability metrics stack to victoria metrics"
```

### Task 6: Prepare deployment and PR handoff

**Files:**
- Modify: none unless implementation reveals a missing repo artifact for deployment instructions

- [ ] **Step 1: Verify branch and worktree state**

Run:

```bash
git status
git branch --show-current
```

Expected: clean working tree on `feat/victoria-metrics-migration` after commit.

- [ ] **Step 2: Push branch and create PR**

Run:

```bash
git push -u origin feat/victoria-metrics-migration
gh pr create --title "feat: migrate observability metrics stack to victoria metrics" --body "$(cat <<'EOF'
## Summary
- replace kube-prometheus-stack with victoria-metrics and a dedicated rules Kustomization
- move custom Prometheus rules into repo-managed manifests and rename the Grafana metrics datasource
- keep the Flux deployment workflow compatible with branch-based testing through the flux-system Kustomization
EOF
)"
```

Expected: branch pushed and PR URL returned.

- [ ] **Step 3: Record the deployment test procedure**

Provide the exact live-cluster test procedure in the final handoff:

```bash
kubectl -n flux-system patch kustomization flux-system --type merge -p '{"spec":{"suspend":true}}'
kubectl -n flux-system patch gitrepository flux-system --type merge -p '{"spec":{"ref":{"branch":"feat/victoria-metrics-migration"}}}'
kubectl -n flux-system patch kustomization flux-system --type merge -p '{"spec":{"suspend":false}}'
flux reconcile source git flux-system -n flux-system
flux reconcile kustomization flux-system -n flux-system --with-source
```

Expected: the final response includes this tested deployment path and the PR link.
