# dev environment/cluster: sandbox k3s hosts (e.g. modules/den/hosts/k3s1.nix)
# that aren't part of the real prd fleet — no routerosDevice belongs to
# this environment, so it carries no real VLAN/router side effects.
# Mirrors modules/den/clusters/prd.nix's shape, minus BGP.
{ den, ... }:
{
  den.environments.dev = {
    domain = "dev.kidibox.net";
    cidrBase = "10.200.0.0/16";
  };

  den.networks.Dev = {
    environment = "dev";
    vlanId = 1;
    domain = "dev.kidibox.net";
  };

  den.clusters.dev = {
    environment = "dev";
    network = "Dev";
    domain = "dev.kidibox.net";

    networks = {
      pods = {
        cidr = "172.30.0.0/16";
        description = "dev k3s pod overlay network";
      };
      services = {
        cidr = "172.31.0.0/16";
        description = "dev k3s service overlay network";
        assignments.coredns = "172.31.0.10";
      };
    };

    bgp.localAsn = 4200000000;

    letsencrypt.staging = true;

    nixidy = {
      repository = "https://github.com/kid/home-ops.git";
      branch = "dev";
      rootPath = "manifests/dev";
    };
  };

  # gateway-api-crds: k3s-bootstrap-crds unconditionally waits for these
  # CRDs to be Established, so they're needed even without apps-gateway's
  # actual Gateway/HTTPRoute objects. No cilium/trust-manager (Hubble-mTLS-
  # only, irrelevant without Cilium as this cluster's CNI), no cilium-bgp
  # (cluster.bgp.peers is empty here), no external-dns/miroir/apps-gateway
  # (not needed for this cluster's purpose).
  den.aspects.dev.includes = with den.aspects.kubernetes; [
    gateway-api-crds
    cert-manager
    coredns
    argocd
    sops-operator
  ];
}
