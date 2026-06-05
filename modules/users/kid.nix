{ den, ... }:
{
  den.aspects.kid = {
    includes = [
      # den.batteries.define-user
      den.batteries.primary-user
      den.batteries.host-aspects
    ];

    # sshKeys = [
    #   "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAcnmLrPeTJeKsasfU0qn4sP4lBNeOUgRG4iZDS8nyEo kid@vulkan"
    #   "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHIM3nsk3HxvEcplSqwynh9V2NzlYdI10mrR746SiJZb kid@fw13"
    # ];
  };
}
