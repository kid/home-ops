# kid user registry entry (den.users.registry fleet pattern — see
# modules/den/schema/users.nix, modules/den/policies/users.nix), and kid's
# user aspect: home-manager with the CLI baseline on every host, plus the
# host's own homeManager content through host-aspects.
{ den, ... }:
{
  den.users.registry.kid = {
    groups = [ "admins" ]; # den.accessGroups, matched against login gates (modules/den/policies/users.nix)
    classes = [ "homeManager" ];
    sshKeys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAcnmLrPeTJeKsasfU0qn4sP4lBNeOUgRG4iZDS8nyEo kid@vulkan"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHIM3nsk3HxvEcplSqwynh9V2NzlYdI10mrR746SiJZb kid@fw13"
    ];
    hashedPassword = "$y$j9T$aTrKe3LPuhd9zCvCSs4KP1$/V7Blv9MLvM5JWQYjLQrTcc2TzrDpcjHdDdqlSP0Aq2";
    displayName = "Arnaud Rebts";
    mail = [ "arnaud.rebts@gmail.com" ];
  };

  den.aspects.kid = {
    includes = [
      den.batteries.host-aspects
      den.aspects.users.privileged
      den.aspects.users.hm-defaults
      den.aspects.profiles.cli
    ];

    homeManager =
      { osConfig, lib, ... }:
      {
        home.stateVersion = osConfig.system.stateVersion;
        systemd.user.startServices = lib.mkDefault "sd-switch";
      };
  };
}
