# nix run .#nixos-anywhere-install <host> <ip> — kexec-based remote NixOS
# install over SSH, directly onto real hardware (no VM, no Terraform-created
# shell). The only "apply this to real infrastructure" surface this repo's
# NixOS/cluster work introduces; does nothing until run by hand.
{ inputs, ... }:
{
  flake-file.inputs.nixos-anywhere.url = "github:nix-community/nixos-anywhere";

  perSystem =
    { system, pkgs, ... }:
    {
      apps.nixos-anywhere-install = {
        type = "app";
        program = "${
          pkgs.writeShellApplication {
            name = "nixos-anywhere-install";
            runtimeInputs = [ inputs.nixos-anywhere.packages.${system}.default ];
            text = ''
              host=''${1:?usage: nixos-anywhere-install <host> <ssh-target, e.g. root@10.0.40.10>}
              target=''${2:?usage: nixos-anywhere-install <host> <ssh-target, e.g. root@10.0.40.10>}
              echo "==> Installing NixOS host '$host' onto $target via nixos-anywhere..."
              nixos-anywhere --flake ".#$host" "$target"
            '';
          }
        }/bin/nixos-anywhere-install";
      };
    };
}
