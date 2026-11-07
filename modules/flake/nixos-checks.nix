# checks.nixos-<host>: build every host's toplevel. `nix flake check` on its
# own only checks that nixosConfigurations.<host> is a derivation, without
# instantiating it, so a package marked broken or a failing build in a host's
# closure got through CI.
{ config, lib, ... }:
{
  perSystem =
    { system, ... }:
    {
      checks =
        config.flake.nixosConfigurations
        |> lib.filterAttrs (_: nixos: nixos.pkgs.stdenv.hostPlatform.system == system)
        |> lib.mapAttrs' (
          name: nixos: lib.nameValuePair "nixos-${name}" nixos.config.system.build.toplevel
        );
    };
}
