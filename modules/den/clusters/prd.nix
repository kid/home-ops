# prd k3s cluster instance, and the VLAN it runs on.
#
# The VLAN declaration lives here rather than in modules/den/networks/prd.nix —
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
{
  den,
  config,
  ...
}:
let
  # host 1 = rb5009's own address on each VLAN (matches rb5009.nix's own
  # `cidrHostPrefixed net 1` for its Management address) — the
  # mikrotik-exporter scrape target talks to the router itself, not crs320.
  # The forward-chain rule below is the only one that actually targets
  # crs320's address.
  rb5009MgmtAddr = config.den.environments.prd.networks.Management.methods.host 1;
  crs320MgmtAddr = config.den.devices.crs320.address;

  # Cilium's LoadBalancer IP pool, BGP-advertised to rb5009 — shared
  # between den.clusters.prd.networks.loadBalancer (read by
  # modules/den/aspects/kubernetes/cilium/bgp.nix) and the firewall forward-rule
  # below, so the two can't drift apart.
  lbCidr = "10.0.42.0/24";
in
{
  den.networks.K3s = {
    environment = "prd";
    vlanId = 40;
    domain = "k3s.home.kidibox.net";
    internetAccess = true;
  };

  den.clusters.prd = {
    environment = "prd";
    network = "K3s";
    domain = "kidibox.net";

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
      loadBalancer = {
        cidr = lbCidr;
        description = "Cilium BGP-advertised LoadBalancer IP pool";
      };
    };

    bgp = {
      localAsn = 64513;
      peers = [
        {
          name = "rb5009";
          ip = "10.0.40.1";
          asn = 64512;
        }
      ];
    };

    nixidy = {
      repository = "https://github.com/kid/home-ops.git";
      branch = "main";
      rootPath = "manifests/prd";
    };
  };

  # cert-manager is included only for Cilium's Hubble mTLS
  # (modules/den/aspects/kubernetes/cert-manager/default.nix) — Helm's own cert
  # generation isn't idempotent across renders. sops-operator provides
  # Kubernetes secrets (modules/den/aspects/kubernetes/sops-operator/default.nix).
  den.aspects.prd.includes = with den.aspects.kubernetes; [
    gateway-api-crds
    cilium
    cilium-bgp
    cilium-egress-gateway
    cilium-host-firewall
    cert-manager
    trust-manager
    coredns
    apps-gateway
    argocd
    miroir
    sops-operator
    external-dns
  ];

  # Cluster-level BGP instance parameters (den.quirks.bgp, modules/den/
  # quirks/bgp.nix), collected onto rb5009 by modules/den/policies/
  # pipes.nix's routeros-device-collect-bgp and consumed by
  # modules/den/aspects/routeros/bgp.nix. Parallels den.aspects.prd.firewall
  # just below: a cluster contributes a small data fragment, the RouterOS
  # side merges fragments from however many clusters/networks apply.
  den.aspects.prd.bgp =
    { cluster, ... }:
    [
      {
        inherit (cluster) name;
        inherit (cluster.bgp)
          localAsn
          peers
          holdTimeSeconds
          keepAliveTimeSeconds
          ;
      }
    ];

  # Router-access rules with no natural single-app owner (mikrotik-exporter
  # isn't its own aspect in this repo; the LB CIDR forward rule is a
  # cluster-wide concern, not tied to one app) — a `firewall` quirk fragment
  # (den.quirks.firewall), collected onto rb5009 by modules/den/policies/
  # pipes.nix's routeros-device-collect-firewall and merged by
  # modules/den/aspects/routeros/firewall.nix into the K3s network's rule
  # lists.
  den.aspects.prd.firewall = { cluster, ... }: [
    {
      inherit (cluster) network;
      input = [
        {
          action = "accept";
          dst_address = rb5009MgmtAddr;
          dst_port = 8729;
          protocol = "tcp";
          comment = "Allow access to Management from K3s for mikrotik-exporter";
        }
      ];
      forward = [
        {
          action = "accept";
          dst_address = lbCidr;
          comment = "Allow Traffic to load balancer ips";
        }
        {
          action = "accept";
          dst_address = crs320MgmtAddr;
          dst_port = 8729;
          protocol = "tcp";
          comment = "Allow access to crs320 for mikrotik-exporter";
        }
      ];
    }
  ];
}
