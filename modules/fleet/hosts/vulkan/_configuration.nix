# vulkan's hardware and networking: VLANs on enp15s0, AMD GPU tuning, gamescope, docker.
{
  pkgs,
  config,
  lib,
  ...
}:
{
  users.privilegedGroups = [ "corectrl" ];

  networking = {
    hostId = "9371deb4";
    useNetworkd = true;
    nftables.enable = true;

    firewall = {
      enable = false;
      allowedTCPPorts = [ 8443 ];
    };
  };

  programs = {
    gamescope.args = lib.mkAfter [
      "-W"
      "3840"
      "-H"
      "2160"
      "-r"
      "138"
      "-f"
      "--adaptive-sync"
      "--force-grab-cursor"
      "--hdr-enabled"
      "--mango"
    ];

    corectrl.enable = true;
  };

  services = {
    resolved.settings.Resolve = {
      DNSSEC = false;
      DNSStubListener = true;
    };

    # udev.extraRules = lib.mkAfter ''
    #   ACTION=="add|change", SUBSYSTEM=="usb", TEST=="power/control", ATTR{power/control}="on"
    #   ACTION=="add|change", SUBSYSTEM=="usb", TEST=="power/wakeup", ATTR{power/wakeup}="disabled"
    #   SUBSYSTEM=="ata_port", KERNEL=="ata*", ATTR{device/power/control}="auto"
    #   ACTION=="add", SUBSYSTEM=="usb", DRIVERS=="usb", ATTR{idVendor}=="cb10", ATTR{idProduct}=="1257", ATTR{power/control}="on"
    # '';

    scx-loader = {
      enable = true;
      config.default_sched = "scx_lavd";
    };

    hardware.openrgb.enable = true;
    smartd.enable = true;
  };

  system.stateVersion = "22.11";

  boot = {
    kernelParams = lib.mkAfter (
      [
        "boot.shell_on_fail"
        # "amdgpu.dcdebugmask=0x400"
        "preempt=full"
        "amd_pstate=active"
      ]
      # HDMI 2.1 FRL ships disabled before 7.4 (DC_FRL_MASK, 0x400); 7.4 defaults to 0x402.
      ++ lib.optional (lib.versionOlder (lib.versions.majorMinor config.boot.kernelPackages.kernel.version) "7.4") "amdgpu.dcfeaturemask=0x402"
    );

    binfmt.emulatedSystems = [ "aarch64-linux" ];

    loader.systemd-boot.windows."11".efiDeviceHandle = "HD0b";
  };

  services.lact.enable = true;
  environment.systemPackages = with pkgs; [
    lact
  ];

  hardware = {
    amdgpu.overdrive.enable = true;
    logitech.wireless = {
      enable = true;
      enableGraphical = true;
    };
  };

  virtualisation = {
    docker.enable = true;
  };
}
