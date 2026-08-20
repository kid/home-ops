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
        { name, ... }:
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
            # CiliumBGPPeerConfig.spec.timers — see modules/network/
            # aspects/ros-bgp.nix and modules/kubernetes/cilium/bgp.nix.
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

            storage = lib.mkOption {
              type = lib.types.attrsOf (
                lib.types.submodule {
                  options = {
                    server = lib.mkOption {
                      type = lib.types.nullOr lib.types.str;
                      default = null;
                    };
                    share = lib.mkOption {
                      type = lib.types.nullOr lib.types.str;
                      default = null;
                    };
                  };
                }
              );
              default = { };
              description = "Storage backends available to this cluster";
            };

            aspect = lib.mkOption {
              type = lib.types.raw;
              default = den.aspects.${name} or { };
              defaultText = "den.aspects.<name>";
              description = "Aspect that configures this cluster (its app-catalog includes)";
            };

            methods = lib.mkOption {
              type = lib.types.attrsOf lib.types.raw;
              default = { };
              description = "Named callables contributed by aspects this cluster includes";
            };
          };
        }
      )
    );
    default = { };
    description = "Kubernetes cluster entity registry for den";
  };
}
