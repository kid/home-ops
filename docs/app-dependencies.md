# Application Dependencies

This diagram shows Flux `Kustomization` application dependencies currently deployed from `clusters/metal/apps`.

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
  kube_prometheus_stack["kube-prometheus-stack"]
  grafana["grafana"]
  grafana_resources["grafana-resources"]
  kubevirt["kubevirt"]
  cdi["cdi"]
  openebs["openebs"]
  volsync["volsync"]
  piraeus_operator["piraeus-operator"]
  nas["nas"]
  mqtt["mqtt"]

  flux_operator --> flux_instance
  cilium --> cilium_resources
  cert_manager --> cert_manager_issuers
  cert_manager --> cloudflare_tunnel
  cert_manager_issuers --> certificates_import
  cert_manager_issuers --> certificates_export
  certificates_import --> certificates_export
  envoy_gateway --> envoy_gateway_resources
  certificates_import --> envoy_gateway_resources
  envoy_gateway --> echo
  envoy_gateway_resources --> echo
  grafana --> grafana_resources
  kubevirt --> cdi
  kubevirt --> nas
  external_secrets --> external_dns_cf
  external_secrets --> external_dns_mikrotik
  external_secrets --> grafana_resources
  volsync --> grafana_resources
```

Notes:

- This includes deployed application kustomizations referenced by `clusters/metal/apps/kustomization.yaml`.
- `frigate` is intentionally omitted because it is commented out in `kubernetes/apps/home-automaton/kustomization.yaml`.
