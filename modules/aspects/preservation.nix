{ inputs, ... }:
{
  flake-file.inputs.preservation.url = "github:nix-community/preservation";

  ops.preservation = {
    nixos =
      { ... }:
      {
        imports = [
          inputs.preservation.nixosModules.preservation
        ];

        fileSystems."/persistent" = {
          neededForBoot = true;
        };

        preservation = {
          enable = true;

          preserveAt."/persistent" = {
            files = [
              {
                file = "/etc/machine-id";
                inInitrd = true;
                how = "symlink";
                configureParent = true;
              }
            ];

            directories = [
              "/var/lib/systemd/timers"
              # NixOS user state
              "/var/lib/nixos"
              "/var/log"
            ];
          };
        };

        systemd.services.systemd-machine-id-commit = {
          unitConfig.ConditionPathIsMountPoint = [
            ""
            "/persistent/etc/machine-id"
          ];
          serviceConfig.ExecStart = [
            ""
            "systemd-machine-id-setup --commit --root /persistent"
          ];
        };
      };
  };
}
