# prd environment instance — split out of modules/den/schema/environments.nix
# (schema/instance split, mirroring nixopslab's modules/den/environments/prod.nix)
# now that prd is referenced by both the RouterOS fleet and the k3s cluster
# entity.
#
# tf-stacks/prd/env.hcl (now removed): env_cidr = cidrsubnet("10.0.0.0/8", 1, 0)
# = "10.0.0.0/9" (deterministic — netnum 0 keeps the same base, just widens
# the prefix by one bit), tld = "home.kidibox.net".
{
  config.den.environments.prd = {
    domain = "home.kidibox.net";
    cidrBase = "10.0.0.0/9";
  };
}
