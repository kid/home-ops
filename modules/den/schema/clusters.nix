# Cluster entity schema and instance registry.
#
# Ported from nixopslab's modules/den/schema/clusters.nix. A cluster is a
# k3s Kubernetes cluster (NixOS hosts, not RouterOS devices) — a sibling
# entity to `network`/`device` under `environment`, sharing the same
# `den.environments.<name>` (see modules/den/policies/fleet.nix's
# `env-to-clusters`).
#
# Deviates from nixopslab in one place: `network` (a string referencing an
# existing `den.networks.<name>` entry) replaces nixopslab's standalone
# `vlanId` int — home-ops already has a richer VLAN/CIDR entity nixopslab
# has no equivalent of, so a cluster resolves its real VLAN/CIDR via
# `config.den.networks.${cluster.network}` /
# `environment.networks.${cluster.network}` instead of duplicating that data.
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
          };
        }
      )
    );
    default = { };
    description = "Kubernetes cluster entity registry for den";
  };
}
