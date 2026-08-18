# Conservative host power-saving: safe on server hardware, no forced ASPM
# or NIC energy-efficient-ethernet (real compatibility risk on trunk NICs).
{
  den.aspects.power-saving.nixos =
    { pkgs, ... }:
    {
      # amd_pstate's "active" driver exposes AMD's CPPC/EPP power control,
      # more efficient than the legacy acpi-cpufreq driver on Zen2+ CPUs.
      # Harmless no-op if the CPU/firmware doesn't support it.
      boot.kernelParams = [ "amd_pstate=active" ];
      powerManagement.cpuFreqGovernor = "powersave";

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
