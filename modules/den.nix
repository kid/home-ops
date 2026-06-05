{
  inputs,
  den,
  lib,
  ...
}:
{
  imports = [
    (inputs.flake-file.flakeModules.dendritic or { })
    (inputs.den.flakeModules.dendritic or { })
    (inputs.den.namespace "ops" true)
  ];

  flake-file.inputs = {
    den.url = "github:denful/den";
    flake-file.url = "github:denful/flake-file";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };

  systems = [ "x86_64-linux" ];

  den.default = {
    includes = [
      den.batteries.define-user
      den.batteries.hostname
    ];
    nixos.system.stateVersion = "26.05";
    homeManager.home.stateVersion = "26.05";
  };

  den.schema.user.classes = lib.mkDefault [ "homeManager" ];
}
