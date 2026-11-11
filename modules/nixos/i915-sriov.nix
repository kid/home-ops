# SR-IOV on an Intel Xe-LP iGPU (node0's Alder Lake UHD 730): mainline i915
# can't create VFs there, strongtz/i915-sriov-dkms's out-of-tree i915 can.
# `host` on the Incus host (the PF), `guest` on each VM given a VF
# (tf-catalog/modules/incus-k3s `gpu_sriov_parent`). Both build the module
# for their own kernel: it supports 6.18 to 7.3 (README "Required kernel"),
# and checks.nixos-<host> fails once a host's kernel leaves that range.
{ inputs, ... }:
let
  # Always the iGPU's address on Intel.
  pf = "0000:00:02.0";
  # One per VM given a VF: the PF splits its resources evenly between them.
  numVfs = 1;
in
{
  flake-file.inputs.i915-sriov = {
    url = "github:strongtz/i915-sriov-dkms/2026.11.05";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  den.aspects.i915-sriov.host.nixos =
    { pkgs, ... }:
    {
      imports = [ inputs.i915-sriov.nixosModules.default ];

      boot.extraModulePackages = [ pkgs.i915-sriov ];
      boot.kernelParams = [
        "intel_iommu=on"
        "i915.enable_guc=3"
        "i915.max_vfs=7"
        "module_blacklist=xe"
      ];
      # GuC firmware, which enable_guc=3 needs.
      hardware.enableRedistributableFirmware = true;

      # Before Incus autostarts the VMs. The VFs stay unbound: Incus only
      # hands out a VF no driver holds, then binds it to vfio-pci itself.
      systemd.services.i915-sriov-vfs = {
        description = "Create the iGPU's SR-IOV VFs";
        wantedBy = [ "multi-user.target" ];
        before = [
          "incus.service"
          "incus-startup.service"
        ];
        path = [ pkgs.kmod ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        # The kernel refuses a new count while VFs exist: a change drops
        # every VF first, so stop the VMs using them before switching.
        script = ''
          modprobe i915
          cd /sys/bus/pci/devices/${pf}
          [ "$(cat sriov_numvfs)" = ${toString numVfs} ] && exit 0
          echo 0 > sriov_drivers_autoprobe
          echo 0 > sriov_numvfs
          echo ${toString numVfs} > sriov_numvfs
        '';
      };
    };

  den.aspects.i915-sriov.guest.nixos =
    { pkgs, ... }:
    {
      imports = [ inputs.i915-sriov.nixosModules.default ];

      boot.extraModulePackages = [ pkgs.i915-sriov ];
      boot.kernelParams = [
        "i915.enable_guc=3"
        "module_blacklist=xe"
      ];

      # The VF's render node by driver: Incus's virtio-gpu has one too, and
      # PCI order decides which is renderD128 (generic-device-plugin).
      services.udev.extraRules = ''
        SUBSYSTEM=="drm", KERNEL=="renderD*", DRIVERS=="i915", SYMLINK+="dri/i915-render"
      '';
    };
}
