# Shell tools every interactive user gets: search, pagers, direnv, prompt.
_: {
  den.aspects.shell = {
    homeManager =
      { pkgs, ... }:
      {
        home.packages = with pkgs; [
          fd
          ripgrep
          jq
          yq
        ];

        programs = {
          bat.enable = true;

          htop.enable = true;

          direnv = {
            enable = true;
            nix-direnv.enable = true;
          };

          eza.enable = true;

          fzf.enable = true;

          starship.enable = true;

          zoxide.enable = true;
        };
      };
  };
}
