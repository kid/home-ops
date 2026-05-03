# Application Dependencies

This diagram shows Flux `Kustomization` application dependencies currently deployed from `clusters/dev/apps`.

```mermaid
graph TD

  flux_operator["flux-operator"]
  flux_instance["flux-instance"]
  cilium["cilium"]
  cilium_resources["cilium-resources"]
  external_secrets["external-secrets"]
  cert_manager["cert-manager"]
  cert_manager_issuers["cert-manager-issuers"]
  certificates_import["certificates-import"]
  certificates_export["certificates-export"]
  envoy_gateway["envoy-gateway"]
  envoy_gateway_resources["envoy-gateway-resources"]
  cloudflare_tunnel["cloudflare-tunnel"]
  external_dns_cf["external-dns-cloudflare"]
  external_dns_mikrotik["external-dns-mikrotik"]
  echo["echo"]
  grafana_operator["grafana-operator"]
  grafana["grafana"]
  mikrotik_exporter["mikrotik-exporter"]
  victoria_metrics["victoria-metrics"]
  victoria_metrics_rules["victoria-metrics-rules"]
  victoria_logs["victoria-logs"]
  victoria_logs_collector["victoria-logs-collector"]
  nfs["nfs"]
  hd_idle["hd-idle"]
  openebs["openebs"]
  external_snapshotter["external-snapshotter"]
  volsync["volsync"]
  piraeus_operator["piraeus-operator"]
  prometheus_operator_crds["prometheus-operator-crds"]

  flux_operator --> flux_instance
  cilium --> cilium_resources
  prometheus_operator_crds --> flux_operator
  prometheus_operator_crds --> cert_manager
  prometheus_operator_crds --> echo
  prometheus_operator_crds --> grafana_operator
  prometheus_operator_crds --> mikrotik_exporter
  cert_manager --> cert_manager_issuers
  cert_manager --> cloudflare_tunnel
  cert_manager_issuers --> certificates_import
  cert_manager_issuers --> certificates_export
  certificates_import --> certificates_export
  envoy_gateway --> envoy_gateway_resources
  certificates_import --> envoy_gateway_resources
  envoy_gateway --> echo
  envoy_gateway_resources --> echo
  grafana_operator --> external_secrets
  grafana_operator --> grafana
  grafana_operator --> external_snapshotter
  grafana_operator --> piraeus_operator
  grafana_operator --> victoria_metrics
  external_secrets --> external_dns_cf
  external_secrets --> external_dns_mikrotik
  external_secrets --> grafana
  external_snapshotter --> volsync
  external_snapshotter --> openebs
  external_snapshotter --> piraeus_operator
  volsync --> grafana
  piraeus_operator --> victoria_metrics
  victoria_metrics --> victoria_metrics_rules
  victoria_logs --> victoria_logs_collector
```

Notes:

- This includes deployed application kustomizations referenced by `clusters/dev/apps/kustomization.yaml`.
- `frigate` is intentionally omitted because it is commented out in `kubernetes/apps/home-automaton/kustomization.yaml`.
