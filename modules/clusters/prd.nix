# prd k3s cluster instance, and the VLAN it runs on.
#
# The VLAN declaration lives here rather than in modules/networks/prd.nix —
# proving den.networks entries are collectible from any entity, not just a
# flat registry, per that module's own original design intent. This is a
# plain Nix module-merge (den.networks.<name> can be set from any file), not
# a new resolve/policy mechanism.
#
# K3s reuses vlanId 40, previously named "Talos" and backing the legacy
# Talos+Flux cluster (clusters/dev/, out of scope here) that this cluster
# replaces. Renaming it is real, live RouterOS infrastructure — see
# tf-stacks/prd/network/rb5009/**/terragrunt.hcl after `write-terragrunt`
# regen; requires a human-reviewed terragrunt plan before apply.
{ den, ... }:
{
  den.networks.K3s = {
    environment = "prd";
    vlanId = 40;
    domain = "k3s.home.kidibox.net";
  };

  den.clusters.prd = {
    environment = "prd";
    network = "K3s";

    networks = {
      pods = {
        cidr = "172.40.0.0/16";
        description = "k3s pod overlay network";
      };
      services = {
        cidr = "172.42.0.0/16";
        description = "k3s service overlay network";
        assignments.coredns = "172.42.0.10";
      };
    };

    bgp.peers = [
      {
        name = "rb5009";
        ip = "10.0.40.1";
        asn = 64512;
      }
    ];

    nixidy = {
      repository = "https://github.com/kid/home-ops.git";
      branch = "main";
      rootPath = "manifests/prd";
    };
  };

  # Minimal app set for this pass (Phase 4 de-risking) — deliberately not
  # cilium-bgp/argocd/cert-manager/external-secrets/openebs/sops-operator
  # yet. See modules/den/aspects/services/k3s-bootstrap.nix (not ported this
  # pass) for why: nixidy's bootstrapManifest assumes ArgoCD exists
  # downstream, so that whole systemd-unit apply chain waits for Phase 5.
  den.aspects.prd.includes = with den.aspects; [
    cilium
    coredns
  ];
}
