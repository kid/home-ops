# The `cloudflare` tofu stack (tf-stacks/cloudflare): account-wide Cloudflare
# resources no cluster owns.
{ den, ... }:
{
  den.tofuStacks.cloudflare = { };

  den.aspects.cloudflare.includes = [ den.aspects.cloudflare.dns ];
}
