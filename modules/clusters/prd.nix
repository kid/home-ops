# prd k3s cluster instance, and the VLAN it runs on.
#
# The VLAN declaration lives here rather than in modules/networks.nix —
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
  # modules/kubernetes/cilium/bgp.nix) and the firewall forward-rule
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
    system-access-groups = [
      "admins"
      "home"
    ];
    network = "K3s";
    domain = "kidibox.net";

    secrets.onepasswordVault = "home-ops-prd";

    # One bare-metal server (k3s-prd-0) and no agents.
    k3s.datastore = "sqlite";

    cloudflare = {
      accountId = "fadfc390b1e5fb0ce019b9f7a8917d42";
      zoneId = "dba2b63221015f1957d718defbf6b871";
      tunnelId = "35161cfa-48b9-45eb-ac15-0574ec58fb7f";
    };

    networks = {
      pods = {
        cidr = "172.40.0.0/16";
        description = "k3s pod overlay network";
      };
      services = {
        cidr = "172.42.0.0/16";
        description = "k3s service overlay network";
        assignments = {
          coredns = "172.42.0.10";
          # VLSingle's journald endpoint for the k3s nodes' journal uploads.
          vlsingle-journald = "172.42.0.11";
        };
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

    # OpenEBS LocalPV-ZFS on k3s-prd-0's zroot/k8s.
    storage = {
      replicatedClass = "zfs";
      localClass = "zfs";
    };

    # Full on-site backups next to r2's, and the claims restore from them:
    # the cluster moved from the Incus VMs onto k3s-prd-0 by restoring every
    # claim from its last `-full` snapshot. Rebuilding without k3s-prd-0's
    # disks means restoreFrom = "r2" (and kopiur.backups = false until the
    # restored apps are verified).
    kopiur.local = true;
    kopiur.restoreFrom = "local";

    nixidy = {
      repository = "https://github.com/kid/home-ops.git";
      branch = "main";
      rootPath = "manifests/prd";
    };
  };

  # cert-manager provides the cluster CA (Hubble mTLS, backend TLS) and the
  # wildcard cert (modules/kubernetes/cert-manager/default.nix) — Helm's own cert
  # generation isn't idempotent across renders. external-secrets provides
  # Kubernetes secrets (modules/kubernetes/external-secrets/default.nix).
  den.aspects.prd.includes = with den.aspects.kubernetes; [
    gateway-api-crds
    cilium
    cilium-bgp
    cilium-host-firewall
    cilium-network-policy
    envoy-gateway
    cert-manager
    trust-manager
    coredns
    flux
    flux-mcp
    flux-webhook
    apiserver
    snapshot-controller
    generic-device-plugin
    zfs-localpv
    external-dns
    external-secrets
    kopiur
    kanidm
    prometheus-operator-crds
    victoria-metrics
    victoria-metrics-mcp
    opentelemetry-collector
    grafana-operator
    grafana-oidc
    cloudflared
    external-dns-cloudflare
    home-assistant.home-assistant
    home-assistant.mosquitto
    home-assistant.zigbee2mqtt
    home-assistant.frigate
    media.prowlarr
    media.animarr
    media.sonarr
    media.radarr
    media.sabnzbd
    media.plex
    media.unpackerr
    media.recyclarr
  ];

  # Rules with no single-app owner: mikrotik-exporter isn't its own aspect here, and the LB CIDR rule is cluster-wide.
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
