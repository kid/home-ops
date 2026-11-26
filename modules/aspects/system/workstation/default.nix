# A personal machine, Linux or Mac: desktop services, packages, sudo, printing and
# the state kept across root wipes. Content only; profiles.workstation composes it.
{ lib, ... }:
{
  # /var/log and /var/lib/nixos are kept in /cache by den.aspects.impermanence.
  den.aspects.workstation.persist.directories = [
    "/var/lib/bluetooth"
    "/var/lib/power-profiles-daemon"
    "/var/lib/fwupd"
    "/var/lib/fprint"
    "/var/lib/sbctl"
    "/etc/secureboot"
    "/var/lib/systemd/coredump"
    "/var/lib/systemd/rfkill"
    "/var/lib/systemd/timers"
  ];

  den.aspects.workstation.os.nixpkgs.config = {
    allowUnfree = true;
    allowBroken = false;
  };

  den.aspects.workstation.homeManager.home.stateVersion = lib.mkDefault "25.05";
  den.aspects.workstation.darwin.system.stateVersion = lib.mkDefault 6;

  den.aspects.workstation.nixos =
    { pkgs, ... }:
    {
      users.mutableUsers = false;

      # The account, password, SSH keys and wheel come from den.users.registry,
      # the shell from the user's profiles.cli.
      users.privilegedGroups = [
        "nix"
        "systemd-journal"
        "audio"
        "pipewire"
        "video"
        "input"
        "lp"
        "docker"
        "gamemode"
      ];

      environment = {
        defaultPackages = lib.mkForce [ ];
        systemPackages = with pkgs; [
          git
          curl
          dnsutils
          usbutils
          ethtool
          lshw
          pciutils
          rsync
          util-linux
          btop
          htop
          watch
          libqalculate
          mangohud
          umu-launcher
          protonup-qt
          powertop
          s-tui
          efibootmgr
          efitools
          efivar
        ];

        variables = {
          NIXPKGS_CONFIG = lib.mkForce "";
          _JAVA_AWT_WM_NONEREPARENTING = "1";
        };
        pathsToLink = [
          "/share/bash-completion"
          "/share/zsh"
        ];
      };

      i18n.defaultLocale = "en_NZ.UTF-8";

      time.timeZone = "Europe/Brussels";

      programs = {
        zsh.enable = true;

        nh = {
          enable = true;
          clean = {
            enable = false;
            dates = "weekly";
          };
        };

        nix-ld.enable = true;

        _1password.enable = true;
        _1password-gui = {
          enable = true;
          polkitPolicyOwners = [ "kid" ];
        };

        kdeconnect.enable = true;
      };

      security = {
        sudo = {
          enable = true;
          wheelNeedsPassword = lib.mkDefault false;
          extraConfig = ''
            Defaults pwfeedback
            Defaults env_keep += "EDITOR PATH DISPLAY"
            Defaults timestamp_timeout = 300
          '';
        };
      };

      services = {
        resolved.enable = true;

        openssh = {
          enable = true;
          startWhenNeeded = true;
          allowSFTP = true;
          settings.PermitRootLogin = "no";
          openFirewall = true;
        };

        printing.enable = true;

        avahi = {
          enable = true;
          nssmdns4 = true;
          openFirewall = true;
        };

        pipewire = {
          audio.enable = true;
          jack.enable = true;
          wireplumber.enable = true;
        };

        pulseaudio.enable = lib.mkForce false;
        power-profiles-daemon.enable = true;
      };

      boot = {
        consoleLogLevel = 3;
        kernelPackages = pkgs.linuxPackages_latest;

        kernel.sysctl = {
          "kernel.nmi_watchdog" = 0;
          "vm.dirty_writeback_centisecs" = 1500;
        };

        loader = {
          efi = {
            canTouchEfiVariables = true;
            efiSysMountPoint = "/boot";
          };

          systemd-boot = {
            configurationLimit = 3;
            consoleMode = "max";
            extraInstallCommands = ''
              ${pkgs.gnused}/bin/sed -E -i 's/default nixos-generation-[0-9]+\.conf/default @saved/g' /boot/loader/loader.conf
            '';
          };
        };

        tmp = {
          useTmpfs = lib.mkDefault false;
          tmpfsSize = lib.mkDefault "50%";
        };
      };

      hardware = {
        enableRedistributableFirmware = true;
        xone.enable = true;
        bluetooth.enable = true;
        printers = {
          ensureDefaultPrinter = "Brother_HL-2030_series";
          ensurePrinters = [
            {
              # The HL-2030's shared queue on home-ops' k3s-prd-0 (Trusted VLAN
              # only), which renders with brlaser. Raw: a driverless
              # (`everywhere`) queue queries the server when created, and
              # would fail cups' start on every boot away from home.
              name = "Brother_HL-2030_series";
              deviceUri = "ipp://k3s-prd-0.k3s.home.kidibox.net/printers/HL-2030";
              model = "raw";
            }
          ];
        };
      };

      powerManagement.scsiLinkPolicy = "med_power_with_dipm";

    };
}
