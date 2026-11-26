# vulkan: kid's AMD gaming desktop, on btrfs with a wiped root.
{
  inputs,
  den,
  lib,
  ...
}:
let
  # Fixed Umbriel workspaces: Mod+1..9 map to "1".."9", Mod+0 to "0" (games).
  # Umbriel puts named workspaces first in dynamic mode, so a trailing one needs a fixed list.
  umbrielWorkspaces = map toString (lib.range 1 9) ++ [ "0" ];
in
{
  flake-file.inputs.nixos-hardware.url = "github:nixos/nixos-hardware";

  den.hosts.x86_64-linux.vulkan = {
    environment = "prd";
    system-access-groups = [ "admins" ];
    settings.disk.btrfs = {
      device = "/dev/disk/by-id/nvme-WD_BLACK_SN8100_2000GB_25264U800487";
      partitionName = "NIXOS";
      subvolumePrefix = "@/";
    };
  };

  # crs320's ether1: Trusted native, Management tagged. Statically addressed
  # by den.aspects.base.network, which also matches the NIC by MAC.
  den.devices.vulkan.interfaces = [
    {
      network = "Trusted";
      hostNum = 20;
      mac = "10:ff:e0:8a:b8:cc";
    }
    {
      network = "Management";
      hostNum = 20;
      mac = "10:ff:e0:8a:b8:cc";
      tagged = true;
    }
  ];

  den.aspects.vulkan = {
    includes = with den.aspects; [
      den.batteries.hostname
      profiles.desktop
      disk.btrfs
      impermanence
      base.network
      dev.libvirt
      hardware.razer
      games.helldivers2
    ];

    persist.directories = [
      "/var/lib/docker"
      "/var/lib/OpenRGB"
    ];

    nixos.imports = [
      ./_configuration.nix
    ]
    ++ (with inputs.nixos-hardware.nixosModules; [
      common-pc
      common-pc-ssd
      common-cpu-amd
      common-cpu-amd-pstate
      common-gpu-amd
    ]);

    homeManager = {
      # programs.umbriel.settings.layout.mode = "master";
      programs.umbriel.settings = {
        output."DP-3" = {
          mode = "3840x2160@138";
          hdr = "on";
          bit_depth = 10;
          vrr = "fullscreen";
          tearing = true;
          workspaces = umbrielWorkspaces;
        };
      };

      programs.plasma.powerdevil.AC = {
        autoSuspend.action = "nothing";
        dimDisplay.enable = false;
        turnOffDisplay.idleTimeout = "never";
      };

      home.sessionVariables = {
        PROTON_FSR4_RDNA3_UPGRADE = "1";
        PROTON_USE_OPTISCALER = "1";
      };
    };
  };
}
