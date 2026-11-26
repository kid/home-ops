# Dagger CLI with Docker; the dagger input is declared in modules/desktop/personal.nix.
{ inputs, den, ... }:
{
  den.aspects.dev.dagger = {
    includes = [ den.aspects.dev.docker ];

    homeManager =
      { pkgs, ... }:
      {
        home.packages = [ inputs.dagger.packages.${pkgs.stdenv.hostPlatform.system}.dagger ];
      };
  };
}
