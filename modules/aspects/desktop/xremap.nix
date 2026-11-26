# xremap per user: Super shortcuts launching the browser and terminal, aware of the host's sessions.
{ inputs, den, ... }:
{
  flake-file.inputs.xremap = {
    url = "github:xremap/nix-flake";
    inputs.nixpkgs.follows = "nixpkgs";
    inputs.flake-parts.follows = "flake-parts";
  };

  den.aspects.desktop.xremap = { host, ... }: {
    nixos = {
      imports = [ inputs.xremap.nixosModules.default ];
      services.xremap.enable = false;
    };

    homeManager =
      { pkgs, ... }:
      let
        scoped =
          cmd:
          [
            "${pkgs.systemd}/bin/systemd-run"
            "--user"
            "--scope"
            "--quiet"
          ]
          ++ cmd;
      in
      {
        imports = [ inputs.xremap.homeManagerModules.default ];

        services.xremap = {
          enable = true;
          withKDE = host.hasAspect den.aspects.desktop.plasma;
          withWlroots = host.hasAspect den.aspects.desktop.umbriel;
          config = {
            # Fix compatibility with Wayland applications (particularly games)
            keypress_delay_ms = 20;
            throttle_ms = 10;

            keymap = [
              {
                remap = {
                  SUPER-B.launch = scoped [ "firefox" ];
                  SUPER-SHIFT-B.launch = scoped [
                    "firefox"
                    "--private-window"
                  ];
                  SUPER-ENTER.launch = scoped [ "wezterm" ];
                };
              }
            ];
          };
        };
      };
  };
}
