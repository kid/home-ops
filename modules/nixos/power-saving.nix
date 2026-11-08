# Host power-saving: CPU biased to efficiency, ASPM on every link that
# tolerates it, but no NIC energy-efficient-ethernet (compatibility risk on
# trunk NICs).
{
  den.aspects.power-saving.nixos =
    { pkgs, ... }:
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

      # The CPU picks its own clocks (HWP/CPPC); bias it fully to efficiency.
      systemd.services.cpu-epp = {
        description = "Set the CPU energy/performance preference to power";
        after = [ "cpufreq.service" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig.Type = "oneshot";
        script = ''
          for f in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
            echo power > "$f"
          done
        '';
      };

      systemd.services.powertop-autotune = {
        description = "Apply powertop's recommended power-saving tunables";
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${pkgs.powertop}/bin/powertop --auto-tune";
        };
      };
    };
}
