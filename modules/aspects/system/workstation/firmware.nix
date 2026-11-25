# AMD/Intel CPU microcode updates from ucodenix.
{ inputs, ... }:
{
  flake-file.inputs = {
    ucodenix.url = "github:e-tho/ucodenix";
  };

  den.aspects.workstation.nixos = {
    imports = [ inputs.ucodenix.nixosModules.default ];

    services.ucodenix.enable = true;
  };
}
