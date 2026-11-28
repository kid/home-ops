# fw13: kid's Framework 13 (AMD AI 300) laptop, on btrfs with a wiped root and
# Secure Boot through lanzaboote. It reaches the homelab remotely through the
# `wg-home` WireGuard profile.
{
  inputs,
  lib,
  den,
  ...
}:
let
  # Fixed Umbriel workspaces: Mod+1..9 map to "1".."9", Mod+0 to "0" (games).
  # Umbriel puts named workspaces first in dynamic mode, so a trailing one needs a fixed list.
  umbrielWorkspaces = map toString (lib.range 1 9) ++ [ "0" ];
in
{
  flake-file.inputs.lanzaboote = {
    url = "github:nix-community/lanzaboote/v1.1.0";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  den.hosts.x86_64-linux.fw13 = {
    environment = "prd";
    system-access-groups = [ "admins" ];
    settings.disk.btrfs = {
      device = "/dev/disk/by-id/nvme-SHPP41-2000GM_ASD9N54741120A36G_1";
      partitionName = "nixos";
      subvolumePrefix = "/";
      persistSubvolume = "persist/system";
    };
  };

  den.aspects.fw13 = {
    includes = with den.aspects; [
      den.batteries.hostname
      profiles.desktop
      disk.btrfs
      impermanence
    ];

    persist.directories = [
      "/etc/NetworkManager/system-connections"
      "/var/lib/iwd"
    ];

    homeManager = {
      programs.plasma.input.touchpads = [
        {
          vendorId = "093A";
          productId = "0274";
          name = "PIXA3854:00 093A:0274 Touchpad";
          naturalScroll = true;
          tapToClick = false;
          rightClickMethod = "twoFingers";
          middleButtonEmulation = true;
        }
      ];

      stylix.fonts.sizes.terminal = 10;

      programs.noctalia.settings.idle.behavior.suspend = {
        timeout = 900;
        action = "lock_and_suspend";
      };

      programs.umbriel.settings = {
        input.touchpad = {
          natural_scroll = true;
          tap = false;
          click_method = "clickfinger";
        };
        output."eDP-1" = {
          scale = 1.5;
          workspaces = umbrielWorkspaces;
        };
        output."DP-2" = {
          vrr = "fullscreen";
          workspaces = umbrielWorkspaces;
        };
      };
    };

    nixos =
      { config, pkgs, ... }:
      {
        imports = [
          inputs.nixos-hardware.nixosModules.framework-amd-ai-300-series
          inputs.lanzaboote.nixosModules.lanzaboote
          inputs.sops-nix.nixosModules.sops
        ];

        # nixfiles' default when fw13 was installed; base defaults to 26.05.
        system.stateVersion = "25.05";

        users.privilegedGroups = [
          "networkmanager"
          "uinput"
          "realtime"
        ];

        environment = {
          systemPackages = lib.mkAfter (
            with pkgs;
            [
              fw-ectool
              config.boot.kernelPackages.cpupower
              sbctl
            ]
          );
        };

        networking = {
          useNetworkd = lib.mkForce false;
          networkmanager.enable = lib.mkForce true;
          networkmanager.wifi.backend = "iwd";
          wireless.iwd.enable = true;

          networkmanager.ensureProfiles = {
            environmentFiles = [ config.sops.templates."wg-home.env".path ];
            # Endpoint, port and addresses mirror routerosInputs.wireguard in modules/fleet/routeros/rb5009.nix.
            profiles.wg-home = {
              connection = {
                id = "wg-home";
                type = "wireguard";
                interface-name = "wg-home";
                autoconnect = "false";
              };
              wireguard.private-key = "$WG_HOME_PRIVATE_KEY";
              "wireguard-peer.XTeAOsV/K63SfrU6obArOj2dIfItwPyr2i/2vrEQygo=" = {
                endpoint = "vpn.home.kidibox.net:51820";
                allowed-ips = "10.0.0.0/16;10.99.0.0/16;";
                persistent-keepalive = "25";
              };
              ipv4 = {
                method = "manual";
                address1 = "10.0.90.2/32";
                dns = "10.0.90.1;";
                dns-search = "~kidibox.net;";
                never-default = "true";
              };
              ipv6.method = "disabled";
            };
          };
        };

        sops = {
          secrets.wg-home-private-key = {
            sopsFile = ../../../secrets/hosts/fw13/wg-home-private-key.sops;
            format = "binary";
          };
          templates."wg-home.env".content = ''
            WG_HOME_PRIVATE_KEY=${config.sops.placeholder.wg-home-private-key}
          '';
        };

        nix = {
          registry =
            (lib.mapAttrs (_: flake: { inherit flake; }) (
              lib.filterAttrs (name: value: lib.types.isType "flake" value && name != "self") inputs
            ))
            // {
              nixpkgs = lib.mkForce { flake = inputs.nixpkgs; };
            };

          settings = {
            extra-platforms = config.boot.binfmt.emulatedSystems;
          };
        };

        security = {
          pam.loginLimits = [
            {
              domain = "@realtime";
              type = "-";
              item = "rtprio";
              value = 98;
            }
            {
              domain = "@realtime";
              type = "-";
              item = "memlock";
              value = "unlimited";
            }
            {
              domain = "@realtime";
              type = "-";
              item = "nice";
              value = -11;
            }
          ];
        };

        services = {
          displayManager = {
            autoLogin = {
              enable = false;
              user = "kid";
            };
            noctalia-greeter = {
              # Lets Noctalia's Settings → Security → Sync push appearance without a password prompt.
              passwordlessSyncUsers = [ "kid" ];
              settings.user.default = "kid";
            };
          };

          udev.extraRules = ''
            KERNEL=="cpu_dma_latency", GROUP="realtime"
          '';

        };

        boot = {
          lanzaboote = {
            enable = true;
            pkiBundle = "/var/lib/sbctl";
          };

          # Firmware drives eDP at the EDID base timing (60 Hz). Keeping fbdev on it lets amdgpu
          # take over without a modeset (DC seamless boot checks the pixel clock); the greeter
          # then switches to the preferred 120 Hz.
          kernelParams = [ "video=eDP-1:2880x1920@60" ];

          loader.systemd-boot.enable = lib.mkForce false;
        };

        hardware = {
          uinput.enable = true;
          sensor.iio.enable = true;
        };

        powerManagement.powertop.enable = true;
      };
  };
}
