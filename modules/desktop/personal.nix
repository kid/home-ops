# kid's desktop programs; host-included, reaches users through host-aspects.
{ inputs, ... }:
{
  flake-file.inputs.dagger = {
    url = "github:dagger/nix";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  den.aspects.desktop.personal.homeManager =
    { pkgs, ... }:
    {
      home.packages =
        with pkgs;
        [
          winbox4
          pistol
          gnumake
          gopls
          devenv
          kubectl
          kubelogin-oidc
          talosctl
          flux
          xclip
          chromium
          discord
          telegram-desktop
          nfs-utils
          pulsemixer
          freecad
          prusa-slicer
          proton-pass
        ]
        ++ [ inputs.dagger.packages.${pkgs.stdenv.hostPlatform.system}.dagger ];

      programs = {
        htop.enable = true;
        btop.enable = true;
        bottom.enable = true;
        k9s.enable = true;
        lf.enable = true;
        kitty.enable = true;
        zellij.enable = true;

        ssh = {
          enable = true;
          enableDefaultConfig = false;
          settings."*" = {
            Compression = true;
            ForwardAgent = true;
          };
        };
      };
    };
}
