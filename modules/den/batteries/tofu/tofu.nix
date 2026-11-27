# "tofu" class: OpenTofu resources an aspect needs outside the cluster
# (Cloudflare tokens, 1Password items, GitHub webhooks, RouterOS users).
# Every aspect a cluster includes adds its own `tofu` content, and all of it
# merges into one root module per cluster, typed by tofunix's options
# generated from each provider's schema. Tofu orders resources by their
# references, so aspects only name each other's resources, never stacks.
#
# The root module is written to tf-stacks/<env>/k3s/main.tf.json by
# `nix run .#write-tofu` (checks.tofu diffs it), and run with
# `just tofu <cluster> <args>`. State is in the same R2 bucket as the
# Terragrunt stacks, at home-ops/<env>/k3s/tofu.tfstate.
#
# Linux only: tofunix builds each provider's schema while evaluating, by
# running tofu on it, so an aarch64-darwin output would need a darwin builder.
{
  lib,
  config,
  den,
  inputs,
  self,
  ...
}:
let
  pins = import ./_providers.nix;

  stackDir = cluster: "tf-stacks/${cluster.environment}/k3s";

  # Terragrunt's remote_state (tf-stacks/root.hcl), minus its own S3 client
  # settings. The endpoint and the credentials come from the environment,
  # out of secrets/cloudflare.sops.yaml (see the tofu-<cluster> app).
  backend = cluster: {
    terraform.backend.s3 = {
      bucket = "terragrunt";
      key = "home-ops/${cluster.environment}/k3s/tofu.tfstate";
      region = "auto";
      encrypt = true;
      use_path_style = true;
      use_lockfile = true;
      skip_credentials_validation = true;
      skip_metadata_api_check = true;
      skip_region_validation = true;
      skip_requesting_account_id = true;
      skip_s3_checksum = true;
    };
  };
in
{
  flake-file.inputs.tofunix = {
    # v3.0.2
    url = "gitlab:TECHNOFAB/tofunix/95c8201f1605c0fadc51fbd03ff117d84ce30735";
    flake = false;
  };

  den.classes.tofu = {
    description = "OpenTofu resources collected into one root module per cluster";
  };

  den.policies.cluster-to-tofu =
    { cluster, ... }:
    lib.optionals cluster.tofu.enable [
      (den.lib.policy.instantiate {
        name = "${cluster.name}-tofu";
        class = "tofu";
        instantiate = { modules, ... }: modules;
        intoAttr = [
          "tofuModules"
          cluster.name
        ];
      })
    ];

  den.schema.cluster.includes = [ den.policies.cluster-to-tofu ];

  perSystem =
    { pkgs, system, ... }:
    let
      tfx = import "${inputs.tofunix}/lib" { inherit pkgs; };

      plugins =
        pins
        |> lib.mapAttrsToList (
          _: pin:
          let
            provider = tfx.mkOpentofuProvider {
              inherit (pin)
                owner
                repo
                version
                hash
                ;
            };
          in
          if pin.patchElf or false then
            provider.overrideAttrs (old: {
              nativeBuildInputs = old.nativeBuildInputs ++ [ pkgs.autoPatchelfHook ];
            })
          else
            provider
        );

      stacks =
        config.flake.tofuModules or { }
        |> lib.mapAttrs (
          name: modules:
          let
            cluster = config.den.clusters.${name};
            module = tfx.mkModule {
              sources = plugins;
              moduleConfig.imports = modules ++ [
                (backend cluster)
                # den's collision validators report through `warnings`.
                {
                  options.warnings = lib.mkOption {
                    type = lib.types.listOf lib.types.str;
                    default = [ ];
                  };
                }
              ];
            };
          in
          {
            dir = stackDir cluster;
            json = lib.foldr lib.warn (pkgs.runCommandLocal "${name}-main.tf.json"
              { nativeBuildInputs = [ pkgs.jq ]; }
              ''
                jq --sort-keys . ${module.config.finalPackage} > $out
              ''
            ) module.config.warnings;
            cli = tfx.mkCli { inherit plugins module; };
          }
        );

      duplicates =
        stacks
        |> lib.mapAttrsToList (name: stack: lib.nameValuePair stack.dir name)
        |> lib.groupBy (p: p.name)
        |> lib.filterAttrs (_: ps: builtins.length ps > 1);

      checkedStacks =
        if duplicates == { } then
          stacks
        else
          throw "tofu stacks rendered more than once: ${
            duplicates
            |> lib.mapAttrsToList (dir: ps: "${dir} (${ps |> map (p: p.value) |> lib.concatStringsSep ", "})")
            |> lib.concatStringsSep "; "
          }. Set den.clusters.<name>.tofu.enable = false on all but one of those clusters.";
    in
    {
      config = lib.mkMerge [
        {
          # Renovate bumps a pin's `version` only; this refreshes its `hash`. Run by
          # rehash-changed-pins for every `datasource=terraform-provider` pin.
          #   rehash-tofu-provider <file> <owner/repo> <version>
          packages.rehash-tofu-provider = pkgs.writeShellApplication {
            name = "rehash-tofu-provider";
            runtimeInputs = [ pkgs.gnused ];
            text = ''
              if [ "$#" -ne 3 ]; then
                echo "usage: rehash-tofu-provider <file> <owner/repo> <version>" >&2
                exit 1
              fi
              file=$1
              dep=$2
              version=$3
              expr="let pkgs = import ${pkgs.path} { }; tfx = import ${inputs.tofunix}/lib { inherit pkgs; }; in tfx.fetchProviderSpec { owner = \"''${dep%%/*}\"; repo = \"''${dep#*/}\"; version = \"$version\"; hash = pkgs.lib.fakeHash; }"
              if output=$(nix-build --no-out-link -E "$expr" 2>&1); then
                echo "$dep@$version: provider spec fetched with a fake hash — unexpected" >&2
                exit 1
              fi
              new_hash=$(grep -oP 'got:\s+\K\S+' <<< "$output" || true)
              if [ -z "$new_hash" ]; then
                echo "could not determine the hash of $dep@$version:" >&2
                echo "$output" >&2
                exit 1
              fi
              sed -i "\|depName=$dep\$|,/hash = \"/{s|hash = \"[^\"]*\";|hash = \"$new_hash\";|}" "$file"
              echo "$file: $dep@$version -> $new_hash"
            '';
          };
        }

        (lib.mkIf (system == "x86_64-linux") {
          packages = {
            write-tofu = pkgs.writeShellApplication {
              name = "write-tofu";
              text =
                checkedStacks
                |> lib.mapAttrsToList (
                  _: stack: ''
                    echo "==> Writing ${stack.dir}/main.tf.json..."
                    mkdir -p "${stack.dir}"
                    install -m 644 "${stack.json}" "${stack.dir}/main.tf.json"
                  ''
                )
                |> lib.concatStrings;
            };
          }
          // lib.mapAttrs' (
            name: stack:
            lib.nameValuePair "tofu-${name}" (
              pkgs.writeShellApplication {
                name = "tofu-${name}";
                runtimeInputs = [
                  pkgs.git
                  pkgs.sops
                ];
                text = ''
                  root=$(git rev-parse --show-toplevel)
                  secrets="$root/secrets/cloudflare.sops.yaml"
                  AWS_ENDPOINT_URL_S3=$(sops --decrypt --extract '["r2_endpoint"]' "$secrets")
                  AWS_ACCESS_KEY_ID=$(sops --decrypt --extract '["r2_access_key"]' "$secrets")
                  AWS_SECRET_ACCESS_KEY=$(sops --decrypt --extract '["r2_secret_key"]' "$secrets")
                  export AWS_ENDPOINT_URL_S3 AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
                  # tofunix runs tofu in a temporary copy, keeping .terraform here.
                  cd "$root/${stack.dir}"
                  exec ${lib.getExe stack.cli} "$@"
                '';
              }
            )
          ) checkedStacks;

          checks.tofu = pkgs.runCommandLocal "tofu-check" { nativeBuildInputs = [ pkgs.diffutils ]; } (
            (
              checkedStacks
              |> lib.mapAttrsToList (
                _: stack: ''
                  if ! diff -q "${self}/${stack.dir}/main.tf.json" "${stack.json}"; then
                    echo "${stack.dir}/main.tf.json is stale — run: nix run .#write-tofu" >&2
                    exit 1
                  fi
                ''
              )
              |> lib.concatStrings
            )
            + "touch $out\n"
          );
        })
      ];
    };
}
