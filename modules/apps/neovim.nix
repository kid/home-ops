# kid's Neovim build (kid/neovim) as the default editor.
{ inputs, ... }:
{
  # Pinned by rev so Renovate bumps it in its own PR (.renovaterc.json5); kid/neovim's CI requests that run on every push to main.
  flake-file.inputs.neovim-flake.url = "github:kid/neovim/cb1a66afc37aeb62a8157d57b8d3fc3bd9d90830";

  den.aspects.apps.neovim = {
    os.nixpkgs.overlays = [ inputs.neovim-flake.overlays.default ];

    homeManager =
      { pkgs, ... }:
      {
        home = {
          packages = with pkgs; [ my-neovim ];
          sessionVariables.EDITOR = "nvim";
          shellAliases.vimdiff = "nvim -d";
        };
      };
  };
}
