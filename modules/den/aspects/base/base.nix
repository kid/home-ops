# Settings common to every host in the fleet.
{ den, ... }:
{
  den.aspects.base.includes = [
    den.aspects.base.security
    den.aspects.base.nix
  ];
}
