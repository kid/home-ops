# Arduino IDE, with serial port access for the privileged user.
_: {
  den.aspects.dev.arduino = {
    nixos.users.privilegedGroups = [ "dialout" ];

    homeManager =
      { pkgs, ... }:
      {
        home.packages = [ pkgs.arduino-ide ];
      };
  };
}
