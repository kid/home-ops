# Renders config.flake.terragruntStacks (modules/den/batteries/terragrunt/terragrunt-stacks.nix) to
# tf-stacks/<env>/network/<routerosDevice>/[<stack>/]terragrunt.hcl and
# (fleet stacks, which no environment owns) tf-stacks/<stack>/terragrunt.hcl,
# exposed as
# `nix run .#write-terragrunt` (mirrors write-manifests/write-terraform
# elsewhere in the dendritic ecosystem) + `checks.terragrunt`
# (diffs generated vs. committed, like checks.terraform/checks.cluster-inventory).
{
  config,
  lib,
  self,
  ...
}:
let
  inherit (import ./_render-lib.nix { inherit lib; }) toValue;

  routerosDevicesByName = config.den.routerosDevices;

  # base sits directly under network/<routerosDevice>/, every other stack
  # nests one level deeper.
  leafRelPath =
    routerosDeviceName: stack:
    let
      envName = routerosDevicesByName.${routerosDeviceName}.environment;
    in
    if stack == "base" then
      "tf-stacks/${envName}/network/${routerosDeviceName}/terragrunt.hcl"
    else
      "tf-stacks/${envName}/network/${routerosDeviceName}/${stack}/terragrunt.hcl";

  # Every RouterOS stack's directory sits one level (base: network/<routerosDevice>/)
  # or two levels (non-base: network/<routerosDevice>/<stack>/) below
  # `network/`; a dependency always targets another device's *base* stack,
  # which always lives directly at network/<toRouterosDevice>/.
  relPathToRouterosDeviceBase =
    {
      fromStack,
      toRouterosDevice,
    }:
    let
      upLevels = if fromStack == "base" then 1 else 2;
    in
    (lib.replicate upLevels "../" |> lib.concatStrings) + toRouterosDevice;

  renderLeaf =
    stack: leaf:
    let
      dependenciesBlock = lib.optionalString ((leaf.dependsOn or [ ]) != [ ]) ''

        dependencies {
          paths = ${
            leaf.dependsOn
            |> map (
              toRouterosDevice:
              relPathToRouterosDeviceBase {
                fromStack = stack;
                inherit toRouterosDevice;
              }
            )
            |> toValue
          }
        }
      '';
      sourceBlock =
        if leaf ? localModule then
          ''
            terraform {
              source = "''${get_repo_root()}/tf-catalog/modules//${leaf.localModule}"
            }
          ''
        else
          ''
            terraform {
              source                   = "git::git@github.com:kid/terragrunt-infra-catalog//modules/${leaf.moduleSource}?ref=${
                leaf.moduleRef or "${leaf.moduleSource}/v${leaf.moduleVersion}"
              }"
              copy_terraform_lock_file = false
            }
          '';
      generateBlock = lib.optionalString (leaf ? generate) ''

        generate "${leaf.generate.label}" {
          path      = "${leaf.generate.path}"
          if_exists = "${leaf.generate.ifExists}"
          contents  = <<-EOF
        ${lib.removeSuffix "\n" leaf.generate.contents}
        EOF
        }
      '';
    in
    ''
      include "root" {
        path = find_in_parent_folders("root.hcl")
      }

      ${sourceBlock}${dependenciesBlock}${generateBlock}
      inputs = ${toValue leaf.inputs}
    '';

  leaves = lib.flatten [
    (lib.mapAttrsToList (
      routerosDeviceName: stacks:
      lib.mapAttrsToList (stack: leaf: {
        path = leafRelPath routerosDeviceName stack;
        content = renderLeaf stack leaf;
      }) stacks
    ) (config.flake.terragruntStacks.network or { }))
    (lib.mapAttrsToList (stack: leaf: {
      path = "tf-stacks/${stack}/terragrunt.hcl";
      content =
        if leaf ? dependsOn then
          throw "fleet stack ${stack}: dependsOn only resolves RouterOS device stacks"
        else
          renderLeaf stack leaf;
    }) (config.flake.terragruntStacks.fleet or { }))
  ];
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
      packages.write-terragrunt = pkgs.writeShellApplication {
        name = "write-terragrunt";
        # Copies each leaf's formatted derivation into place (rather than
        # a heredoc) so the written byte content matches
        # checks.terragrunt's own comparison target exactly.
        text = lib.concatMapStrings (leaf: ''
          echo "==> Writing ${leaf.path}..."
          mkdir -p "$(dirname "${leaf.path}")"
          install -m 644 "${formattedLeaf leaf}" "${leaf.path}"
        '') leaves;
      };

      checks.terragrunt =
        pkgs.runCommandLocal "terragrunt-check" { nativeBuildInputs = [ pkgs.diffutils ]; }
          (
            lib.concatMapStrings (leaf: ''
              if ! diff -q "${self}/${leaf.path}" "${formattedLeaf leaf}"; then
                echo "${leaf.path} is stale — run: nix run .#write-terragrunt" >&2
                exit 1
              fi
            '') leaves
            + "\ntouch $out"
          );
    };
}
