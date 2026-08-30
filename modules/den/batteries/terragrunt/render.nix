# Exposes modules/terragrunt/_render-lib.nix's HCL renderer as a top-level
# module arg (`{ hcl, ... }:`), for device modules like
# modules/den/routerosDevices/rb5009.nix that need `hcl.raw` outside of `perSystem`.
{ lib, ... }:
{
  _module.args.hcl = import ./_render-lib.nix { inherit lib; };
}
