# Renders config.flake.terragruntStacks (modules/terragrunt/collect.nix) to
# tf-stacks/<env>/network/<device>/[<stack>/]terragrunt.hcl, exposed as
# `nix run .#write-terragrunt` (mirrors apps.write-manifests/write-terraform
# elsewhere in the dendritic ecosystem) + `checks.terragrunt` (diffs
# generated vs. committed, like checks.terraform/checks.cluster-inventory).
{
  config,
  lib,
  self,
  ...
}:
let
  inherit (import ./_render-lib.nix { inherit lib; }) toValue;

  devicesByName = config.den.devices;

  leafRelPath =
    deviceName: stack:
    let
      envName = devicesByName.${deviceName}.environment;
    in
    if stack == "base" then
      "tf-stacks/${envName}/network/${deviceName}/terragrunt.hcl"
    else
      "tf-stacks/${envName}/network/${deviceName}/${stack}/terragrunt.hcl";

  # Every stack's directory sits one level (base: network/<device>/) or two
  # levels (non-base: network/<device>/<stack>/) below `network/`; a
  # dependency always targets another device's *base* stack, which always
  # lives directly at network/<toDevice>/.
  relPathToDeviceBase =
    {
      fromStack,
      toDevice,
    }:
    let
      upLevels = if fromStack == "base" then 1 else 2;
    in
    (lib.concatStrings (lib.replicate upLevels "../")) + toDevice;

  renderLeaf =
    _deviceName: stack: leaf:
    let
      dependenciesBlock = lib.optionalString (leaf.dependsOn != [ ]) ''

        dependencies {
          paths = ${
            toValue (
              map (
                toDevice:
                relPathToDeviceBase {
                  fromStack = stack;
                  inherit toDevice;
                }
              ) leaf.dependsOn
            )
          }
        }
      '';
    in
    ''
      include "root" {
        path = find_in_parent_folders("root.hcl")
      }

      terraform {
        source                   = "git::git@github.com:kid/terragrunt-infra-catalog//modules/${leaf.moduleSource}?ref=${
          leaf.moduleRef or "${leaf.moduleSource}/v${leaf.moduleVersion}"
        }"
        copy_terraform_lock_file = false
      }
      ${dependenciesBlock}
      inputs = ${toValue leaf.inputs}
    '';

  allLeaves = lib.flatten (
    lib.mapAttrsToList (
      deviceName: stacks:
      lib.mapAttrsToList (stack: leaf: {
        path = leafRelPath deviceName stack;
        content = renderLeaf deviceName stack leaf;
      }) stacks
    ) (config.flake.terragruntStacks or { })
  );
in
{
  perSystem =
    { pkgs, ... }:
    let
      # treefmt's hclfmt formatter (modules/flake/devshell.nix) covers *.hcl
      # repo-wide, so the committed leaves must already be hclfmt-clean —
      # format at render time so write-terragrunt's output and
      # checks.terragrunt's comparison target agree with treefmt.
      formattedLeaf =
        leaf:
        pkgs.runCommandLocal "terragrunt-leaf" { nativeBuildInputs = [ pkgs.hclfmt ]; } ''
          hclfmt ${pkgs.writeText "terragrunt-leaf-raw" leaf.content} > $out
        '';
    in
    {
      apps.write-terragrunt = {
        type = "app";
        program = "${
          pkgs.writeShellApplication {
            name = "write-terragrunt";
            # Copies each leaf's formatted derivation into place (rather than
            # a heredoc) so the written byte content matches
            # checks.terragrunt's own comparison target exactly.
            text = lib.concatMapStrings (leaf: ''
              echo "==> Writing ${leaf.path}..."
              mkdir -p "$(dirname "${leaf.path}")"
              install -m 644 "${formattedLeaf leaf}" "${leaf.path}"
            '') allLeaves;
          }
        }/bin/write-terragrunt";
      };

      checks.terragrunt =
        pkgs.runCommandLocal "terragrunt-check" { nativeBuildInputs = [ pkgs.diffutils ]; }
          (
            lib.concatMapStrings (leaf: ''
              if ! diff -q "${self}/${leaf.path}" "${formattedLeaf leaf}"; then
                echo "${leaf.path} is stale — run: nix run .#write-terragrunt" >&2
                exit 1
              fi
            '') allLeaves
            + "\ntouch $out"
          );
    };
}
