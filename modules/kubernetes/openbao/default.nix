# OpenBao, self-hosted secrets backend for ESO — replaces the 1Password-direct
# design (see external-secrets-1password branch/PR #230): avoids 1Password's
# API rate limits, which have caused real problems before. Raft integrated
# storage with a single replica: not for HA (this is a single-node cluster),
# but Raft is OpenBao's actively-maintained storage engine (unlike the legacy
# "file" backend used by the chart's default "standalone" mode) and gives a
# real snapshot/restore story via `bao operator raft snapshot`.
#
# No auto-unseal: a home lab has no external KMS to auto-unseal against, and
# per-decision the unseal key is deliberately kept off node1 entirely (sops,
# encrypted only to human machines — see secrets/prd/openbao-init.sops.yaml).
# Unsealing after every restart is a manual `bao operator unseal`, run by a
# human against the fixed address below — there is no NixOS/systemd
# automation for it here, by design.
#
# Fixed LoadBalancer IP (Cilium's io.cilium/lb-ipam-ips, matching the pool
# modules/kubernetes/cilium/bgp.nix already advertises) + a static RouterOS
# DNS record (modules/routerosDevices/rb5009.nix's dns_static_records) give
# OpenTofu (run by hand from a human's laptop, same convention as every other
# Terraform stack in this repo) a stable address to configure OpenBao at,
# without needing external-dns.
_: {
  den.aspects.openbao.k8s-manifests =
    { charts, ... }:
    {
      applications.openbao = {
        namespace = "openbao";
        createNamespace = true;

        helm.releases.openbao = {
          chart = charts.openbao.openbao;
          values = {
            server = {
              replicas = 1;

              ha = {
                enabled = true;
                replicas = 1;
                raft.enabled = true;
              };

              dataStorage.storageClass = "openebs-zfs";

              service = {
                type = "LoadBalancer";
                # 10.0.42.10: first manually-reserved address in
                # den.clusters.prd.networks.loadBalancer.cidr
                # (modules/clusters/prd.nix, 10.0.42.0/24) — nothing else in
                # this pool uses a fixed IP yet, so this is a fresh
                # reservation, not derived from any existing allocation.
                annotations."io.cilium/lb-ipam-ips" = "10.0.42.10";
              };
            };
          };
        };
      };
    };
}
