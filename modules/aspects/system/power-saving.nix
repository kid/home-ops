# Host power-saving: CPU biased to efficiency, ASPM on every link that
# tolerates it, powertop's recommended tunables, but no NIC
# energy-efficient-ethernet (compatibility risk on trunk NICs).
{ lib, ... }:
{
  den.aspects.power-saving = {
    settings.cpuEpp = lib.mkOption {
      type = lib.types.enum [
        "power"
        "balance_power"
        "balance_performance"
        "performance"
      ];
      default = "power";
      description = ''
        CPU energy/performance preference (HWP/CPPC). `power` holds an i3-12100
        at ~1.2 GHz even when fully busy: too slow for a host whose pods keep it
        loaded.
      '';
    };

    nixos =
      { host, ... }:
      {
        boot.kernelParams = [
          # amd_pstate's "active" driver exposes AMD's CPPC/EPP power control,
          # more efficient than the legacy acpi-cpufreq driver on Zen2+ CPUs.
          # Harmless no-op if the CPU/firmware doesn't support it.
          "amd_pstate=active"
          # The default policy keeps the BIOS's ASPM setup, which leaves node1's
          # X570 uplink and X550 at L0 and blocks enabling them through sysfs.
          # The kernel still skips states an endpoint's exit latency can't take.
          "pcie_aspm.policy=powersupersave"
        ];
        powerManagement.cpuFreqGovernor = "powersave";

        # The CPU picks its own clocks (HWP/CPPC); bias it per settings.cpuEpp.
        systemd.services.cpu-epp = {
          description = "Set the CPU energy/performance preference to ${host.settings.power-saving.cpuEpp}";
          after = [ "cpufreq.service" ];
          wantedBy = [ "multi-user.target" ];
          serviceConfig.Type = "oneshot";
          script = ''
            for f in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
              echo ${host.settings.power-saving.cpuEpp} > "$f"
            done
          '';
        };

        # What `powertop --auto-tune` applied on k3s-prd-0 (its "Optimal Tuned
        # Software Settings"), declared so every change is reviewed here.
        boot.kernel.sysctl = {
          "kernel.nmi_watchdog" = 0;
          "vm.dirty_writeback_centisecs" = 1500;
        };
        # Runtime PM for every PCI device, USB device and SCSI disk. Applied
        # when a device appears, so new ones get it too.
        services.udev.extraRules = ''
          ACTION=="add", SUBSYSTEM=="pci", ATTR{power/control}="auto"
          ACTION=="add", SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", ATTR{power/control}="auto"
          ACTION=="add", SUBSYSTEM=="scsi", ENV{DEVTYPE}=="scsi_device", ATTR{type}=="0", ATTR{power/control}="auto"
        '';
      };
  };
}
