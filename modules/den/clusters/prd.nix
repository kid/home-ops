# prd k3s cluster instance, and the VLAN it runs on.
#
# The VLAN declaration lives here rather than in modules/den/networks.nix —
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
  lib,
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

  macOf =
    host: network:
    (lib.findFirst (i: i.network == network) null config.den.devices.${host}.interfaces).mac;

  # Provisions the Incus VLAN + k3s VM node1 runs this cluster on. Not owned
  # by any single Kubernetes app, so it lives here rather than under
  # aspects/kubernetes/ — a small local aspect object appended to includes
  # below, the same shape as nixidy-defaults.nix's nixidyDefaultsAspect.
  # VLANs, MACs and addresses come from den.networks/den.devices; node1's
  # Incus remote address, the physical NIC name and the VM sizing have no
  # Nix source and stay literal.
  incusTerragruntAspect = {
    name = "prd/incus";
    "terragrunt-stacks" = { cluster, ... }: {
      stack = "incus";
      localModule = "incus-k3s";
      generate = {
        label = "incus_provider";
        path = "incus_provider.tf";
        ifExists = "overwrite_terragrunt";
        contents = ''
          provider "incus" {
            default_remote = "node1"

            remote {
              name    = "node1"
              address = "https://10.0.10.10:8443"
            }

            remote {
              name     = "images"
              address  = "https://images.linuxcontainers.org"
              protocol = "simplestreams"
            }
          }
        '';
      };
      inputs = {
        networks.k3s = {
          name = "k3s-${cluster.name}";
          parent = "enp36s0f1";
          vlan_id = config.den.networks.K3s.vlanId;
        };
        networks.storage = {
          name = "storage-${cluster.name}";
          parent = "enp36s0f1";
          vlan_id = config.den.networks.Storage.vlanId;
          inherit (config.den.networks.Storage) mtu;
        };
        nodes = {
          # 40G root LV (den.aspects.incus-vm), the rest for miroir.
          "k3s-${cluster.name}-0" = {
            nixos_attr = "k3s-${cluster.name}-0";
            cpu = 4;
            memory = "16GiB";
            disk_size = "64GiB";
            mac = macOf "k3s-${cluster.name}-0" "K3s";
            inherit (config.den.devices."k3s-${cluster.name}-0") address;
            extra_nics.storage.mac = macOf "k3s-${cluster.name}-0" "Storage";
          };
          "k3s-${cluster.name}-1" = {
            nixos_attr = "k3s-${cluster.name}-1";
            cpu = 4;
            memory = "8GiB";
            disk_size = "64GiB";
            mac = macOf "k3s-${cluster.name}-1" "K3s";
            inherit (config.den.devices."k3s-${cluster.name}-1") address;
            extra_nics.storage.mac = macOf "k3s-${cluster.name}-1" "Storage";
          };
        };
        storage_pool = "default";
        ssh_authorized_keys = lib.unique (
          lib.concatMap (u: u.sshKeys) (lib.attrValues config.den.users.registry)
        );
      };
    };
  };
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

    secrets.onepasswordVault = "home-ops-prd";

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

  # cert-manager provides the cluster CA (Hubble mTLS, backend TLS) and the
  # wildcard cert (modules/den/aspects/kubernetes/cert-manager/default.nix) — Helm's own cert
  # generation isn't idempotent across renders. external-secrets provides
  # Kubernetes secrets (modules/den/aspects/kubernetes/external-secrets/default.nix).
  den.aspects.prd.includes =
    (with den.aspects.kubernetes; [
      gateway-api-crds
      cilium
      cilium-bgp
      cilium-host-firewall
      cilium-network-policy
      envoy-gateway
      cert-manager
      trust-manager
      coredns
      argocd
      argocd-oidc
      apiserver
      snapshot-controller
      miroir
      external-dns
      external-secrets
      kopiur
      authelia
      kanidm
      prometheus-operator-crds
      victoria-metrics
      mcp
      grafana-operator
      grafana-oidc
      cloudflared
      external-dns-cloudflare
    ])
    ++ [ incusTerragruntAspect ];

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
