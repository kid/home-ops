# Environment entity schema and instance registry.
#
# Mirrors nixopslab's modules/den/schema/environments.nix. An environment
# groups networks and devices that share a base CIDR block and domain TLD
# (e.g. "prd", one day "dev"). `cidrBase` is the environment-wide supernet
# every network's own /prefix is carved out of (see modules/network/lib.nix
# cidrsubnet), matching tf-stacks/prd/env.hcl's `env_cidr`.
#
# `networks` resolves every den.networks entry belonging to this environment
# (filtered by name, not by scope-tree resolution — env-to-networks in
# modules/den/policies/fleet.nix does the scope-tree walk separately, for
# future collectibility) and computes its cidr from cidrBase/vlanId/prefix.
# Device aspects read `environment.networks.<name>` for vlan/cidr data.
{
  lib,
  tf,
  config,
  cidrLib,
  ...
}:
let
  # `config` inside the submodule below is the environment's own resolved
  # config (shadowing this one) — capture the flake-root config here so
  # `default` can still reach config.den.networks.
  rootConfig = config;
in
{
  config.den.schema.environment.isEntity = true;

  # tf-stacks/prd/env.hcl: env_cidr = cidrsubnet("10.0.0.0/8", 1, 0) = "10.0.0.0/9"
  # (deterministic — netnum 0 keeps the same base, just widens the prefix by
  # one bit), tld = "home.kidibox.net".
  config.den.environments.prd = {
    domain = "home.kidibox.net";
    cidrBase = "10.0.0.0/9";
  };

  options.den.environments = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule (
        { name, config, ... }:
        {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              default = name;
              description = "Environment name";
            };

            domain = lib.mkOption {
              type = lib.types.str;
              description = "Base domain TLD for this environment (e.g. home.kidibox.net)";
            };

            cidrBase = lib.mkOption {
              type = lib.types.str;
              description = "Supernet every network in this environment carves its /prefix out of";
            };

            networks = lib.mkOption {
              type = lib.types.attrsOf lib.types.raw;
              default =
                let
                  envPrefixLength = cidrLib.prefixLength config.cidrBase;
                  ownNetworks = lib.filterAttrs (_: net: net.environment == config.name) rootConfig.den.networks;
                  withComputedCidr =
                    net:
                    net
                    // {
                      cidr =
                        if !net.routed then
                          null
                        else if net.cidr != null then
                          net.cidr
                        else
                          cidrLib.cidrsubnet config.cidrBase (net.prefix - envPrefixLength) net.vlanId;
                    };
                in
                lib.mapAttrs (_: withComputedCidr) ownNetworks;
              defaultText = "computed from den.networks";
              description = "This environment's networks, keyed by name, with cidr resolved";
            };

            aspect = lib.mkOption {
              type = lib.types.raw;
              default = tf.${name} or { };
              defaultText = "tf.<name>";
              description = "Aspect that configures this environment";
            };
          };
        }
      )
    );
    default = { };
    description = "Environment entity registry for den";
  };
}
