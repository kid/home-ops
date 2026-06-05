{
  den,
  ops,
  inputs,
  ...
}:
{
  flake-file.inputs.impermanence.url = "github:nix-community/impermanence";

  ops.impermanence = {
    nixos =
      { ... }:
      {
        imports = [
          inputs.impermanence.nixosModules.impermanence
        ];

        fileSystems."/persistent" = {
          neededForBoot = true;
        };

        virtualisation.vmVariantWithDisko = {
          virtualisation.fileSystems."/persistent".neededForBoot = true;
        };

        environment.persistence."/persistent" = {
          enable = true;
          files = [
            "/etc/machine-id"
          ];
          directories = [
            "/var/lib/systemd/timers"
            # NixOS user state
            "/var/lib/nixos"
            "/var/log"
          ];
        };
      };

    includes = [
      # FIXME: not working
      (den.lib.policy.when ({ host, ... }: host.hasAspect ops.disko) {
        nixos =
          { ... }:
          {
            virtualisation.vmVariantWithDisko = {
              virtualisation.fileSystems."/persistent".neededForBoot = true;
            };
          };
      })
    ];
  };
}
