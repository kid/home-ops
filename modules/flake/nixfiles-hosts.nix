# Temporary: deploys kid/nixfiles' desktops from home-ops, unchanged, until
# they are ported to den hosts here. Removed once fw13 is ported.
# No follows: the toplevels stay exactly the ones nixfiles builds.
{ inputs, ... }:
{
  flake-file.inputs.nixfiles.url = "github:kid/nixfiles";

  flake.nixosConfigurations = { inherit (inputs.nixfiles.nixosConfigurations) vulkan fw13; };
}
