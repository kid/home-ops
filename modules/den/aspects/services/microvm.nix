# microvm.nix hypervisor side. Guests are not declared here (no
# microvm.vms.<name>): each stays its own nixosConfigurations entry,
# installed and updated with its microvm.deploy.* scripts, so a host deploy
# never rebuilds or restarts a guest.
{ inputs, ... }:
{
  flake-file.inputs.microvm = {
    url = "github:microvm-nix/microvm.nix/f13928fe9900e91709d7ce581eefa47eaafa79e1";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  den.aspects.microvm-host = {
    datasets."zroot/microvm" = {
      mountpoint = "/var/lib/microvms";
      properties.mountpoint = "legacy";
    };

    nixos = {
      imports = [ inputs.microvm.nixosModules.host ];

      microvm.host.enable = true;
    };
  };
}
