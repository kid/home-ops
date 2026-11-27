# The fleet entity's own aspect: what sits above every environment
# (modules/den/policies/fleet.nix), like account-wide Cloudflare records.
{ den, ... }:
{
  den.aspects.fleet.includes = [ den.aspects.cloudflare.dns ];
}
