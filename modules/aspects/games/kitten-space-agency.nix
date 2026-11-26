# Kitten Space Agency, packaged locally (pkgs/kitten-space-agency).
_: {
  den.aspects.games.kitten-space-agency = {
    homeManager =
      { pkgs, ... }:
      {
        home.packages = [ (pkgs.callPackage ../../../pkgs/kitten-space-agency/package.nix { }) ];
      };
  };
}
