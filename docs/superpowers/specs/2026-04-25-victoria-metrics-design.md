# VictoriaMetrics Migration Design

## Goal

Replace `kube-prometheus-stack` with VictoriaMetrics while keeping Prometheus Operator CRDs (`ServiceMonitor`, `PrometheusRule`) as the repo contract, preserving kube-prometheus-derived dashboards and recording/alerting rules, and keeping Grafana as the primary query and alert-management UI.

## Current State

- `kube-prometheus-stack` is deployed from `kubernetes/apps/observability/kube-prometheus-stack/`.
- Grafana is deployed separately and provisioned through repo-managed resources under `kubernetes/apps/observability/grafana/`.
- App-local monitoring configuration is still expressed primarily as `ServiceMonitor` objects.
- There are checked-in custom `PrometheusRule` manifests, and additional custom rules are currently embedded in the `kube-prometheus-stack` Helm values.
- The current Prometheus deployment uses persistent storage on `linstor-zfs-ssd`.
- `cert-manager` already exists as a Flux-managed dependency in `network-system`.

## Chosen Approach

Use `victoria-metrics-k8s-stack` as the replacement for `kube-prometheus-stack`.

This approach is preferred because the chart already includes:

- VictoriaMetrics Operator
- `VMSingle`
- `VMAgent`
- `VMAlert`
- `VMAlertmanager`
- kube-prometheus-derived dashboards and rules
- automatic conversion of existing Prometheus Operator objects into VictoriaMetrics operator objects

This keeps the repo contract stable while minimizing app-level churn.

## Architecture

### Flux apps

Create two new observability Flux apps:

1. `victoria-metrics`
2. `victoria-metrics-rules`

`victoria-metrics` installs the `victoria-metrics-k8s-stack` Helm chart and owns the core VictoriaMetrics deployment.

`victoria-metrics-rules` is a separate Flux Kustomization containing repo-managed custom `PrometheusRule` manifests. It must `dependsOn` `victoria-metrics` so the operator, CRDs, and conversion machinery are present before custom rules reconcile.

### Repo layout

```text
kubernetes/apps/observability/victoria-metrics/ks.app.yaml
kubernetes/apps/observability/victoria-metrics/app/kustomization.yaml
kubernetes/apps/observability/victoria-metrics/app/prometheus-operator-crds-ocirepository.yaml
kubernetes/apps/observability/victoria-metrics/app/prometheus-operator-crds-helmrelease.yaml
kubernetes/apps/observability/victoria-metrics/app/ocirepository.yaml
kubernetes/apps/observability/victoria-metrics/app/helmrelease.yaml
kubernetes/apps/observability/victoria-metrics-rules/ks.app.yaml
kubernetes/apps/observability/victoria-metrics-rules/app/kustomization.yaml
kubernetes/apps/observability/victoria-metrics-rules/app/*.yaml
```

### Dependencies

`victoria-metrics` must depend on:

- `cert-manager` in `network-system`
- `grafana` in `observability`, because the VictoriaMetrics chart will emit `GrafanaDashboard` CRs through grafana-operator integration
- the storage-side Flux Kustomization that guarantees `linstor-zfs-ssd` exists before PVC binding, currently `piraeus-operator`

`victoria-metrics` must also bootstrap Prometheus Operator CRDs explicitly with a dedicated `prometheus-operator-crds` HelmRelease so the cluster still supports `ServiceMonitor` and `PrometheusRule` after `kube-prometheus-stack` is removed.

`victoria-metrics-rules` must depend on:

- `victoria-metrics`

### Grafana integration

- Keep the existing Grafana deployment and Grafana Operator resources.
- Disable the chart-bundled Grafana.
- Replace the existing Prometheus datasource with a VictoriaMetrics datasource definition.
- Keep the datasource type as `prometheus` so Grafana alerting support remains compatible.
- Update existing `GrafanaDashboard` resources in the repo to use the new datasource name instead of relying on the old `Prometheus` name.

Grafana remains the only user-facing metrics UI. The `prometheus.${APP_DOMAIN}` route is not preserved.

## Rules Strategy

### Default rules

Keep the kube-prometheus-derived default dashboards, recording rules, and alerting rules supplied by `victoria-metrics-k8s-stack`.

### Custom rules

Move custom rules currently embedded in `kubernetes/apps/observability/kube-prometheus-stack/app/helmrelease.yaml` out of chart values and into first-class repo-managed `PrometheusRule` manifests under `victoria-metrics-rules`.

Existing standalone `PrometheusRule` manifests elsewhere in the repo, such as the VolSync rules, remain unchanged.

### Rule execution

Keep `VMAlert` enabled.

`grafana-operator` is not a replacement for `VMAlert` in this design because it provisions Grafana-managed alerting resources rather than evaluating preserved `PrometheusRule` objects. Preserving kube-prometheus-style rules requires `VMAlert`.

### Notifications

Use chart-managed `VMAlertmanager` for alert notifications.

Grafana can integrate with that Alertmanager for management and visibility, but it does not replace `VMAlert` for evaluating the preserved rule set.

## Storage Strategy

- Keep persistent storage for the VictoriaMetrics backend.
- Use `linstor-zfs-ssd` to match the current Prometheus storage intent.
- Keep retention broadly aligned with the current setup unless sizing or chart defaults require a small adjustment during implementation.

## cert-manager Strategy

- Enable cert-manager support in `victoria-metrics-k8s-stack` for operator webhook certificates.
- Prefer cert-manager-backed webhook certificates over chart self-signed certificates.
- Ensure the Flux dependency graph guarantees `cert-manager` is healthy before `victoria-metrics` reconciles.

## Testing and Deployment Strategy

### Goal

Exercise the migration through the real Flux path without immediately replacing the production-tracked branch.

### Branch-based Flux sync test

Use a temporary Git branch and patch the live Flux source to point at that branch for testing.

Because the live `GitRepository` source is managed by the `flux-system` Kustomization, the safe procedure is:

1. Create a dedicated test branch containing the VictoriaMetrics migration.
2. Suspend the live `flux-system` Kustomization to stop it from reconciling the `GitRepository` back to the normal branch.
3. Patch the live `GitRepository` branch/ref to the test branch.
4. Resume and reconcile the relevant Flux objects.
5. Validate the deployment.
6. Either revert the branch reference or merge once the test succeeds.

Only the `flux-system` Kustomization needs to be suspended for this handoff; suspending the `GitRepository` is unnecessary because `flux-system` is the object that would otherwise reset the source configuration.

### Shadow validation

Use a short-lived side-by-side validation window before cutover:

1. Keep `kube-prometheus-stack` running initially.
2. Deploy `victoria-metrics` with bundled Grafana disabled.
3. Add a temporary Grafana datasource pointing at VictoriaMetrics for comparison.
4. Reconcile `victoria-metrics-rules` only after the main stack is healthy.
5. Compare representative dashboards, raw queries, and recording-rule outputs.
6. Replace the old Prometheus datasource with the new VictoriaMetrics datasource and update repo-managed dashboards accordingly.
7. Remove `kube-prometheus-stack` after the cutover is stable.

This creates a brief period of double-scraping, which is acceptable for a controlled migration window in this cluster.

## Verification

Before cluster rollout, use the repo-local checks from `dagger/flux-local/main.go`:

- `flux-local test -A --enable-helm --path clusters/dev`
- `flux-local build all --skip-invalid-kustomization-paths --enable-helm clusters/dev`

During validation:

- confirm `victoria-metrics` is healthy
- confirm `victoria-metrics-rules` is healthy
- confirm PVCs bind on `linstor-zfs-ssd`
- confirm the Prometheus Operator CRDs remain accepted
- confirm `ServiceMonitor` objects are discovered and converted
- confirm custom `PrometheusRule` objects reconcile and are loaded by `VMAlert`
- confirm Grafana can query VictoriaMetrics
- confirm repo-managed `GrafanaDashboard` resources reference the renamed datasource consistently

## Risks and Mitigations

### Missing storage dependency ordering

Risk: the VictoriaMetrics PVC may reconcile before `linstor-zfs-ssd` exists.

Mitigation: add an explicit dependency on the storage Kustomization that owns the storage class.

### Broken Grafana dashboards

Risk: dashboards fail if the datasource is renamed but repo-managed `GrafanaDashboard` resources still reference the old name.

Mitigation: rename the datasource deliberately and update existing `GrafanaDashboard` resources in the repo as part of the migration.

### Rules reconciling too early

Risk: custom `PrometheusRule` manifests reconcile before the operator and conversion layer are ready.

Mitigation: put custom rules in `victoria-metrics-rules` with `dependsOn: victoria-metrics`.

### Webhook certificate churn

Risk: operator webhook cert management is noisy or unstable if left self-signed.

Mitigation: enable cert-manager support and depend on `cert-manager`.

### Missing Prometheus Operator CRDs on fresh bootstrap

Risk: the migration works only as an in-place upgrade because `ServiceMonitor` and `PrometheusRule` CRDs were previously left behind by `kube-prometheus-stack`.

Mitigation: install the Prometheus Operator CRDs explicitly as part of `victoria-metrics`.

## Out of Scope

- Migrating app manifests from `ServiceMonitor` to VictoriaMetrics-native CRDs
- Rewriting preserved Prometheus-style rules into Grafana-managed alerting
- Preserving the Prometheus HTTP UI endpoint
