# dev k3s cluster instance: a single sqlite server on bare-metal node1
# (modules/hosts/node1.nix), on the K3sDev VLAN (modules/networks.nix).
#
# Lives on the long-lived `dev` branch only, never merged: Flux syncs
# manifests/dev from that branch. It proves the destroy-and-recreate path —
# a fresh cluster restoring its app data from kopiur's r2 repository —
# before prd moves onto node1.
#
# It reuses prd's cloud resources and 1Password items (vault home-ops-prd,
# the same Cloudflare account and zone, kopiur's R2 bucket), so it renders
# no terragrunt stacks of its own (terragrunt.enable) and never writes to
# the shared kopiur repository (kopiur.backups): restores only.
#
# Infra only for now. Left out on purpose: cilium-host-firewall (node1 is
# bare metal, a bad policy locks the host out), apiserver/Kanidm (no Kanidm
# here: kubectl through the k3s admin kubeconfig over ssh), miroir
# (zfs-localpv instead), cloudflared, external-dns, flux-webhook and
# monitoring. prometheus-operator-crds stays: the charts' ServiceMonitors
# don't apply without their CRD.
{ den, ... }:
let
  # Cilium's LoadBalancer IP pool, BGP-advertised to rb5009 — shared between
  # den.clusters.dev.networks.loadBalancer and the firewall forward-rule
  # below. 10.0.42.0/24 is prd's; neither /24 is a VLAN.
  lbCidr = "10.0.43.0/24";
in
{
  den.clusters.dev = {
    environment = "prd";
    system-access-groups = [
      "admins"
      "home"
    ];
    network = "K3sDev";
    domain = "dev.kidibox.net";

    secrets.onepasswordVault = "home-ops-prd";

    cloudflare = {
      accountId = "fadfc390b1e5fb0ce019b9f7a8917d42";
      zoneId = "dba2b63221015f1957d718defbf6b871";
      tunnelId = "35161cfa-48b9-45eb-ac15-0574ec58fb7f";
    };

    networks = {
      pods = {
        cidr = "172.44.0.0/16";
        description = "k3s pod overlay network";
      };
      services = {
        cidr = "172.46.0.0/16";
        description = "k3s service overlay network";
        assignments.coredns = "172.46.0.10";
      };
      loadBalancer = {
        cidr = lbCidr;
        description = "Cilium BGP-advertised LoadBalancer IP pool";
      };
    };

    bgp = {
      localAsn = 64514;
      peers = [
        {
          name = "rb5009";
          ip = "10.0.41.1";
          asn = 64512;
        }
      ];
    };

    k3s.datastore = "sqlite";
    terragrunt.enable = false;
    letsencrypt.staging = true;
    kopiur.backups = false;

    storage = {
      replicatedClass = "zfs";
      localClass = "zfs";
    };

    nixidy = {
      repository = "https://github.com/kid/home-ops.git";
      branch = "dev";
      rootPath = "manifests/dev";
    };
  };

  den.aspects.dev.includes = with den.aspects.kubernetes; [
    gateway-api-crds
    cilium
    cilium-bgp
    cilium-network-policy
    envoy-gateway
    cert-manager
    trust-manager
    coredns
    flux
    snapshot-controller
    zfs-localpv
    external-secrets
    kopiur
    prometheus-operator-crds
    # Restore drill: its claim fills from prd's latest r2 snapshot.
    media.prowlarr
  ];

  den.aspects.dev.firewall = { cluster, ... }: [
    {
      inherit (cluster) network;
      forward = [
        {
          action = "accept";
          dst_address = lbCidr;
          comment = "Allow Traffic to load balancer ips";
        }
      ];
    }
  ];
}
