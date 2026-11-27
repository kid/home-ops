# "tofu" class: OpenTofu resources an aspect needs outside NixOS and the
# cluster's manifests (Cloudflare tokens, 1Password items, GitHub webhooks,
# RouterOS configuration). Each den entity that owns a stack collects its
# aspects' content into one root module, typed by tofunix's options generated
# from each provider's schema. Tofu orders resources by their references, so
# aspects only name each other's resources, never stacks.
#
# One stack per entity:
#   - a cluster: class `tofu`, tf-stacks/<env>/k3s;
#   - a RouterOS device: class `tofu`, tf-stacks/routeros/<device>;
#   - the fleet: class `fleet-tofu`, tf-stacks/fleet. Its own class, since an
#     instantiate collects its class from the whole subtree, and the fleet's
#     is every cluster's and device's.
# Each root module is written to <dir>/main.tf.json by `nix run .#write-flake`
# (a flake-file write hook; checks.tofu diffs it) and run with
# `just tofu <dir under tf-stacks, dashed> <args>`, e.g. `just tofu
# routeros-rb5009 plan`. State is in R2, at home-ops/<dir under tf-stacks>/tofu.tfstate.
# The evaluated stacks are at tofuStacks.{k3s.<cluster>,routeros.<device>,fleet}.
#
# Linux only: tofunix builds each provider's schema while evaluating, by
# running tofu on it, so an aarch64-darwin output would need a darwin builder.
{
  lib,
  config,
  den,
  inputs,
  self,
  withSystem,
  ...
}:
let
  pins = import ./_providers.nix;

  # The R2 bucket the stacks keep their state in. The endpoint and the
  # credentials come from the environment, out of secrets/cloudflare.sops.yaml
  # (see the tofu-<stack> apps).
  backend = dir: {
    terraform.backend.s3 = {
      bucket = "terragrunt";
      key = "home-ops/${lib.removePrefix "tf-stacks/" dir}/tofu.tfstate";
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

  # Blocks tofunix has no options for, passed through to main.tf.json as
  # written: `module` (e.g. a catalog module a stack still calls), and
  # `moved`/`import` (state moves and adoptions).
  extraBlocks =
    { config, ... }:
    {
      options = {
        module = lib.mkOption {
          type = lib.types.attrsOf (lib.types.attrsOf lib.types.anything);
          default = { };
        };
        moved = lib.mkOption {
          type = lib.types.listOf (lib.types.attrsOf lib.types.str);
          default = [ ];
        };
        import = lib.mkOption {
          type = lib.types.listOf (lib.types.attrsOf lib.types.anything);
          default = [ ];
        };
        # den's collision validators report through `warnings`.
        warnings = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
        };
      };
      config.final = lib.filterAttrs (_: v: v != { } && v != [ ]) {
        inherit (config) module moved import;
      };
    };

  # tofunix and the pinned providers, built for pkgs' platform. `plugins`
  # are typed (tofunix generates options from their schemas); `cliPlugins`
  # adds the untyped ones a stack only reaches through a module it calls.
  tofunixFor =
    pkgs:
    let
      tfx = import "${inputs.tofunix}/lib" { inherit pkgs; };

      provider =
        pin:
        if pin ? sha256 then
          tfx.mkTerraformProvider {
            inherit (pin)
              owner
              repo
              version
              registry
              ;
            src = pkgs.fetchurl {
              url = "https://github.com/${pin.owner}/terraform-provider-${pin.repo}/releases/download/v${pin.version}/terraform-provider-${pin.repo}_${pin.version}_${pkgs.go.GOOS}_${pkgs.go.GOARCH}.zip";
              inherit (pin) sha256;
            };
          }
        else
          let
            fetched = tfx.mkOpentofuProvider {
              inherit (pin)
                owner
                repo
                version
                hash
                ;
            };
          in
          if pin.patchElf or false then
            fetched.overrideAttrs (old: {
              nativeBuildInputs = old.nativeBuildInputs ++ [ pkgs.autoPatchelfHook ];
            })
          else
            fetched;

      typed = lib.filterAttrs (_: pin: !(pin.untyped or false)) pins;
    in
    {
      inherit tfx;
      plugins = typed |> lib.mapAttrsToList (_: provider);
      cliPlugins = pins |> lib.mapAttrsToList (_: provider);
      # tofu with the given providers, for tofunix's mkCli. Unlike nixpkgs'
      # opentofu.withPlugins, keeps each provider under its own registry:
      # that one files registry.terraform.io providers under
      # registry.opentofu.org, where a module requiring
      # registry.terraform.io/ebogdum/routeros doesn't look.
      tf-pkg.withPlugins =
        plugins:
        pkgs.writeShellApplication {
          name = "tofu";
          text = ''
            NIX_TERRAFORM_PLUGIN_DIR=${
              pkgs.symlinkJoin {
                name = "tofu-providers";
                paths = plugins null |> map (p: "${p}/libexec/terraform-providers");
              }
            } exec ${lib.getExe pkgs.opentofu} "$@"
          '';
        };
    };

  # Evaluates an entity's collected content into its stack, rooted at `dir`.
  instantiateStack =
    {
      name,
      class,
      dir,
      intoAttr,
    }:
    den.lib.policy.instantiate {
      inherit name class intoAttr;
      instantiate =
        { modules, ... }:
        withSystem "x86_64-linux" (
          { pkgs, ... }:
          let
            inherit (tofunixFor pkgs) tfx plugins;
          in
          tfx.mkModule {
            sources = plugins;
            moduleConfig.imports = modules ++ [
              (backend dir)
              extraBlocks
            ];
          }
          // {
            inherit dir;
          }
        );
    };

  # Every stack, keyed by its app name: tofu-<dir under tf-stacks, dashed>.
  stacks =
    let
      all =
        (lib.attrValues (config.flake.tofuStacks.k3s or { }))
        ++ (lib.attrValues (config.flake.tofuStacks.routeros or { }))
        ++ lib.optional (config.flake.tofuStacks ? fleet) config.flake.tofuStacks.fleet;

      named =
        all
        |> map (
          module:
          lib.nameValuePair "tofu-${module.dir |> lib.removePrefix "tf-stacks/" |> lib.replaceStrings [ "/" ] [ "-" ]}" module
        );

      duplicates =
        named
        |> lib.groupBy (p: p.name)
        |> lib.filterAttrs (_: ps: builtins.length ps > 1)
        |> builtins.attrNames;
    in
    if duplicates != [ ] then
      throw "tofu stacks rendered more than once: ${lib.concatStringsSep ", " duplicates}. Set den.clusters.<name>.tofu.enable = false on all but one of the clusters sharing an environment."
    else
      named |> lib.listToAttrs;

  stackJson =
    pkgs: module:
    lib.foldr lib.warn (pkgs.runCommandLocal "main.tf.json" { nativeBuildInputs = [ pkgs.jq ]; } ''
      jq --sort-keys . ${module.config.finalPackage} > $out
    '') module.config.warnings;
in
{
  flake-file.inputs.tofunix = {
    # v3.0.2
    url = "gitlab:TECHNOFAB/tofunix/95c8201f1605c0fadc51fbd03ff117d84ce30735";
    flake = false;
  };

  den.classes.tofu = {
    description = "OpenTofu resources collected into one root module per cluster or RouterOS device";
  };
  den.classes.fleet-tofu = {
    description = "OpenTofu resources no environment owns, collected into the fleet's root module";
  };

  den.policies.cluster-to-tofu =
    { cluster, ... }:
    lib.optionals cluster.tofu.enable [
      (instantiateStack {
        name = "${cluster.name}-tofu";
        class = "tofu";
        dir = "tf-stacks/${cluster.environment}/k3s";
        intoAttr = [
          "tofuStacks"
          "k3s"
          cluster.name
        ];
      })
    ];

  den.policies.routeros-device-to-tofu =
    { routerosDevice, ... }:
    [
      (instantiateStack {
        name = "${routerosDevice.name}-tofu";
        class = "tofu";
        dir = "tf-stacks/routeros/${routerosDevice.name}";
        intoAttr = [
          "tofuStacks"
          "routeros"
          routerosDevice.name
        ];
      })
    ];

  # The fleet has a single entity, so its stack has no entity-name segment.
  # Needs the fleet bound to den.aspects.fleet (modules/den/policies/fleet.nix).
  den.policies.fleet-to-tofu = _: [
    (instantiateStack {
      name = "fleet-tofu";
      class = "fleet-tofu";
      dir = "tf-stacks/fleet";
      intoAttr = [
        "tofuStacks"
        "fleet"
      ];
    })
  ];

  den.schema.cluster.includes = [ den.policies.cluster-to-tofu ];
  den.schema.routerosDevice.includes = [ den.policies.routeros-device-to-tofu ];
  den.schema.fleet.includes = [ den.policies.fleet-to-tofu ];

  # `nix run .#write-flake` also writes every stack's main.tf.json. Elsewhere
  # than on x86_64-linux it skips them, since they only evaluate there.
  flake-file.write-hooks = [
    {
      index = 200;
      program =
        pkgs:
        pkgs.writeShellApplication {
          name = "write-tofu-stacks";
          text =
            if pkgs.stdenv.hostPlatform.system == "x86_64-linux" then
              stacks
              |> lib.mapAttrsToList (
                _: module: ''
                  echo "==> Writing ${module.dir}/main.tf.json..."
                  mkdir -p "${module.dir}"
                  install -m 644 "${stackJson pkgs module}" "${module.dir}/main.tf.json"
                ''
              )
              |> lib.concatStrings
            else
              ''echo "Skipping the tofu stacks: they only evaluate on x86_64-linux" >&2'';
        };
    }
  ];

  perSystem =
    { pkgs, system, ... }:
    let
      inherit (tofunixFor pkgs) tfx cliPlugins tf-pkg;
    in
    {
      config = lib.mkMerge [
        {
          # Renovate bumps a pin's `version` only; this refreshes its `hash`
          # (the OpenTofu registry's metadata for the version) or, for a pin
          # fetched from registry.terraform.io, its `sha256` (the linux_amd64
          # zip's, as that registry publishes it). Run by rehash-changed-pins
          # for every `datasource=terraform-provider` pin.
          #   rehash-tofu-provider <file> <owner/repo> <version>
          packages.rehash-tofu-provider = pkgs.writeShellApplication {
            name = "rehash-tofu-provider";
            runtimeInputs = [
              pkgs.gnused
              pkgs.curl
              pkgs.jq
            ];
            text = ''
              if [ "$#" -ne 3 ]; then
                echo "usage: rehash-tofu-provider <file> <owner/repo> <version>" >&2
                exit 1
              fi
              file=$1
              dep=$2
              version=$3
              block=$(sed -n "\|depName=$dep\$|,/}/p" "$file")
              if grep -q 'sha256 = ' <<< "$block"; then
                new=$(curl -fsS "https://registry.terraform.io/v1/providers/$dep/$version/download/linux/amd64" | jq -r .shasum)
                sed -i "\|depName=$dep\$|,/sha256 = \"/{s|sha256 = \"[^\"]*\";|sha256 = \"$new\";|}" "$file"
              else
                expr="let pkgs = import ${pkgs.path} { }; tfx = import ${inputs.tofunix}/lib { inherit pkgs; }; in tfx.fetchProviderSpec { owner = \"''${dep%%/*}\"; repo = \"''${dep#*/}\"; version = \"$version\"; hash = pkgs.lib.fakeHash; }"
                if output=$(nix-build --no-out-link -E "$expr" 2>&1); then
                  echo "$dep@$version: provider spec fetched with a fake hash — unexpected" >&2
                  exit 1
                fi
                new=$(grep -oP 'got:\s+\K\S+' <<< "$output" || true)
                if [ -z "$new" ]; then
                  echo "could not determine the hash of $dep@$version:" >&2
                  echo "$output" >&2
                  exit 1
                fi
                sed -i "\|depName=$dep\$|,/hash = \"/{s|hash = \"[^\"]*\";|hash = \"$new\";|}" "$file"
              fi
              echo "$file: $dep@$version -> $new"
            '';
          };
        }

        (lib.mkIf (system == "x86_64-linux") {
          packages = lib.mapAttrs (
            app: module:
            pkgs.writeShellApplication {
              name = app;
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
                cd "$root/${module.dir}"
                exec ${
                  lib.getExe (
                    tfx.mkCli {
                      inherit tf-pkg module;
                      plugins = cliPlugins;
                    }
                  )
                } "$@"
              '';
            }
          ) stacks;

          checks.tofu = pkgs.runCommandLocal "tofu-check" { nativeBuildInputs = [ pkgs.diffutils ]; } (
            (
              stacks
              |> lib.mapAttrsToList (
                _: module: ''
                  if ! diff -q "${self}/${module.dir}/main.tf.json" "${stackJson pkgs module}"; then
                    echo "${module.dir}/main.tf.json is stale — run: nix run .#write-flake" >&2
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
