# Cluster entity schema and instance registry. A cluster is a k3s
# Kubernetes cluster (NixOS hosts, not RouterOS devices) — a sibling entity
# to `network`/`routerosDevice` under `environment`, sharing the same
# `den.environments.<name>` (see modules/den/policies/fleet.nix's
# `env-to-clusters`).
#
# `network` (a string referencing an existing `den.networks.<name>` entry)
# resolves this cluster's real VLAN/CIDR via
# `config.den.networks.${cluster.network}` /
# `environment.networks.${cluster.network}`, rather than duplicating that
# data as a standalone field.
{ lib, den, ... }:
{
  config.den.schema.cluster.isEntity = true;

  options.den.clusters = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule (
        { name, config, ... }:
        {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              default = name;
              description = "Cluster name";
            };

            environment = lib.mkOption {
              type = lib.types.str;
              description = "Name of the den.environments entry this cluster belongs to";
            };

            network = lib.mkOption {
              type = lib.types.str;
              description = "Name of the den.networks entry this cluster's nodes attach to";
            };

            system-access-groups = lib.mkOption {
              type = lib.types.listOf (lib.types.enum (builtins.attrNames den.accessGroups));
              default = [ ];
              description = "Kanidm login gates for this cluster, added to its environment's";
            };

            networks = lib.mkOption {
              type = lib.types.attrsOf (
                lib.types.submodule {
                  options = {
                    cidr = lib.mkOption {
                      type = lib.types.str;
                      description = "Overlay CIDR (e.g. k3s pod or service CIDR)";
                    };
                    description = lib.mkOption {
                      type = lib.types.str;
                      default = "";
                    };
                    assignments = lib.mkOption {
                      type = lib.types.attrsOf lib.types.str;
                      default = { };
                      description = "Fixed IPs pinned within this overlay (e.g. coredns clusterIP)";
                    };
                  };
                }
              );
              default = { };
              description = "This cluster's k3s overlay networks (pods/services), keyed by purpose";
            };

            domain = lib.mkOption {
              type = lib.types.str;
              description = "Public domain this cluster's DNS-record-managing apps (e.g. external-dns) operate against";
            };

            nixidy = lib.mkOption {
              type = lib.types.submodule {
                options = {
                  repository = lib.mkOption {
                    type = lib.types.str;
                    description = "Git URL nixidy targets for this cluster's rendered manifests";
                  };
                  branch = lib.mkOption {
                    type = lib.types.str;
                    default = "main";
                  };
                  rootPath = lib.mkOption {
                    type = lib.types.str;
                    description = "Directory (within repository) nixidy renders manifests to";
                  };
                };
              };
              description = "nixidy target for this cluster's rendered manifests";
            };

            bgp.peers = lib.mkOption {
              type = lib.types.listOf (
                lib.types.submodule {
                  options = {
                    name = lib.mkOption { type = lib.types.str; };
                    ip = lib.mkOption { type = lib.types.str; };
                    asn = lib.mkOption { type = lib.types.int; };
                  };
                }
              );
              default = [ ];
              description = "BGP peers this cluster's CNI advertises pod/service routes to";
            };

            bgp.localAsn = lib.mkOption {
              type = lib.types.int;
              description = "Local ASN this cluster's CNI (Cilium) BGP instance advertises as, when peering with bgp.peers";
            };

            # Single source of truth for BGP session timers, fed to both
            # the RouterOS side (terragrunt-infra-catalog's talos-bgp
            # module's bgp_hold_time/bgp_keepalive_time) and Cilium's own
            # CiliumBGPPeerConfig.spec.timers — see
            # modules/routeros/bgp.nix and modules/kubernetes/cilium/bgp.nix.
            bgp.holdTimeSeconds = lib.mkOption {
              type = lib.types.int;
              default = 90;
              description = "BGP hold time (seconds), applied identically on both BGP peers";
            };

            bgp.keepAliveTimeSeconds = lib.mkOption {
              type = lib.types.int;
              default = 30;
              description = "BGP keepalive time (seconds), applied identically on both BGP peers";
            };

            k3s.initServer = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "The server (den.hosts name) that creates this cluster's etcd datastore; the other servers join it, so all of them can be declared and started together. null: only a cluster's single declared server creates it (see modules/nixos/services/k3s/k3s.nix). Only for datastore = \"etcd\".";
            };

            k3s.datastore = lib.mkOption {
              type = lib.types.enum [
                "etcd"
                "sqlite"
              ];
              default = "etcd";
              description = "k3s datastore. etcd: embedded etcd (clusterInit), so more servers can join. sqlite: k3s's default SQLite on its only server, with no etcd ports or etcd metrics; the cluster can never have a second server.";
            };

            terragrunt.enable = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Render this cluster's own terragrunt stacks (tf-stacks/<env>/k3s/<stack>, modules/den/batteries/terragrunt). Off for a cluster that reuses another one's cloud resources and 1Password items: the stack paths have no cluster segment, so two clusters of one environment can't both render the same stack.";
            };

            egressGateways = lib.mkOption {
              type = lib.types.attrsOf (lib.types.attrsOf lib.types.str);
              default = { };
              example.home-assistant = {
                k3s-prd-0 = "10.0.40.20";
                k3s-prd-1 = "10.0.40.21";
              };
              description = "Dedicated egress IPs on the cluster's network (outside its DHCP pool), keyed by the app that leaves through them, then by k3s node (den.hosts name). Each is added as a /32 on its node (modules/nixos/services/k3s/egress-gateway.nix, which also asserts every node has one) and used by a CiliumEgressGatewayPolicy for the app's pods on that node, so its traffic leaves from the node it runs on and RouterOS rules can match that app alone. Open-source Cilium has no gateway failover, hence one per node.";
            };

            letsencrypt.staging = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Use Let's Encrypt's staging ACME server instead of production (modules/kubernetes/cert-manager)";
            };

            secrets.onepasswordVault = lib.mkOption {
              type = lib.types.str;
              description = "1Password vault name this cluster's ExternalSecrets read from (modules/kubernetes/external-secrets)";
            };

            cloudflare = {
              accountId = lib.mkOption {
                type = lib.types.str;
                description = "Cloudflare account ID holding this cluster's R2 bucket (modules/kubernetes/kopiur)";
              };
              zoneId = lib.mkOption {
                type = lib.types.str;
                description = "ID of the Cloudflare zone for `domain`, where cert-manager solves DNS-01";
              };
              tunnelId = lib.mkOption {
                type = lib.types.str;
                description = "Cloudflare Tunnel ID for this cluster's public ingress (modules/kubernetes/cloudflared) — hand-copied once from the cloudflared terragrunt stack's `tunnel_id` output after its bootstrap apply. Not sensitive on its own: it ends up published in public DNS CNAMEs anyway.";
              };
            };

            storage = {
              replicatedClass = lib.mkOption {
                type = lib.types.str;
                description = "StorageClass of every app volume (mkKopiurBackup claims, Kanidm, VMSingle, VLSingle)";
              };
              localClass = lib.mkOption {
                type = lib.types.str;
                description = "Node-local StorageClass for throwaway copies: kopiur's staged backup snapshots";
              };
            };

            aspect = lib.mkOption {
              type = lib.types.raw;
              default = den.aspects.${name} or { };
              defaultText = "den.aspects.<name>";
              description = "Aspect that configures this cluster (its app-catalog includes)";
            };

            # Keyed like den's own hasAspect (nix/lib/aspects/has-aspect.nix):
            # a den.aspects reference and the resolved entry in an includes
            # list are different values, so they are compared by aspect path.
            includesAspect = lib.mkOption {
              type = lib.types.functionTo lib.types.bool;
              readOnly = true;
              default =
                let
                  inherit (den.lib.aspects.fx.identity) aspectPath pathKey;
                  key = ref: if ref ? name && ref ? meta then pathKey (aspectPath ref) else pathKey ref.__aspectChain;
                in
                ref: lib.elem (key ref) (map key (config.aspect.includes or [ ]));
              defaultText = "aspect: whether den.aspects.<name>.includes lists it";
              description = "Whether this cluster's own aspect includes the given aspect (e.g. den.aspects.kubernetes.apiserver) directly";
            };

            methods = lib.mkOption {
              type = lib.types.attrsOf lib.types.raw;
              default = { };
              description = "Named callables for this cluster's aspects: every den.clusterMethods entry applied to this cluster, plus any set here directly";
            };
          };

          config.methods = lib.mapAttrs (_: mkMethod: mkMethod config) den.clusterMethods;
        }
      )
    );
    default = { };
    description = "Kubernetes cluster entity registry for den";
  };

  # Lets an aspect file give every cluster a method without naming clusters:
  # setting den.clusters.<name>.methods from a file that reads den.clusters to
  # find the names would recurse forever.
  options.den.clusterMethods = lib.mkOption {
    type = lib.types.lazyAttrsOf lib.types.raw;
    default = { };
    description = "Methods every cluster gets as den.clusters.<name>.methods.<method>: each is a function from the cluster (its den.clusters entry) to the method. They are lazy, so a cluster that doesn't include the providing aspect just never calls it.";
  };
}
