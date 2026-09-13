# prd environment instance — split out of modules/den/schema/environments.nix
# (schema/instance split, mirroring nixopslab's modules/den/environments/prod.nix)
# now that prd is referenced by both the RouterOS fleet and the k3s cluster
# entity.
#
# tf-stacks/prd/env.hcl (now removed): env_cidr = cidrsubnet("10.0.0.0/8", 1, 0)
# = "10.0.0.0/9" (deterministic — netnum 0 keeps the same base, just widens
# the prefix by one bit), tld = "home.kidibox.net".
{
  config,
  den,
  ...
}:
let
  environment = config.den.environments.prd;
in
{
  config = {
    den.environments.prd = {
      domain = "home.kidibox.net";
      cidrBase = "10.0.0.0/9";
    };

    # den.aspects.prd is shared with the "prd" cluster entity (clusters.nix
    # sets den.aspects.prd.includes/.firewall/.bgp too — same instance name,
    # disambiguated by terragrunt-stacks content class, not aspect key).
    den.aspects.prd = {
      includes = [ den.aspects.zerotierNetwork ];

      terragruntInputs."zerotier-network" = {
        dependsOn = [ ];
        inputs = {
          op_vault = "home-ops";
          op_item_zerotier_central = "ZeroTier Central - API Token";
          network_name = "home-lan";
          # TODO: rb5009's `identity_public` output, once its zerotier stack
          # (modules/den/routerosDevices/rb5009.nix) is applied.
          router_member_id = "TODO-rb5009-zerotier-identity";
          router_ip = "10.147.20.1"; # matches rb5009.nix's zerotierIp
          assignment_pool = {
            start = "10.147.20.2";
            end = "10.147.20.254";
          };
          routes = map (n: { target = environment.networks.${n}.cidr; }) [
            "Trusted"
            "Servers"
            "Management"
          ];
        };
      };
    };
  };
}
