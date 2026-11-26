# Temporary: deploys kid/nixfiles' fw13 from home-ops, unchanged, until it
# is ported to a den host here. Removed once fw13 is ported.
# No follows: the toplevels stay exactly the ones nixfiles builds.
{ inputs, ... }:
{
  flake-file.inputs.nixfiles.url = "github:kid/nixfiles";

  flake.nixosConfigurations = { inherit (inputs.nixfiles.nixosConfigurations) fw13; };
}
