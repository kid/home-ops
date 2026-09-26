# terragrunt-stacks class + collection policies.
#
# Modeled on nixopslab's modules/terranix/collect.nix host-to-terranix
# policy: registers "terragrunt-stacks" as an aspect content class directly
# on den.classes (no private namespace — see AGENTS.md), and collects it
# across two entity kinds' aspect-includes chains:
#   - a routerosDevice (den.aspects.<routerosDevice>.includes = [
#     den.aspects.routeros.base den.aspects.routeros.capsman ... ]) into
#     config.flake.terragruntStacks.network.<routerosDevice>.<stack>, git-ref
#     sourced from the private terragrunt-infra-catalog repo.
#   - a cluster (den.aspects.<cluster>.includes = [ den.aspects.kubernetes.
#     cert-manager ... ]) into config.flake.terragruntStacks.k3s.<cluster>.
#     <stack>, path-sourced from this repo's own tf-catalog/modules/.
# Nested under "network"/"k3s" (rather than a flat attrset keyed by entity
# name) so a routerosDevice and a cluster can never collide on name.
#
# `terragruntInputs` is a reserved (non-class) aspect key: each routerosDevice's
# own self-aspect (modules/den/routerosDevices/*.nix) precomputes its per-stack
# {dependsOn, inputs} data there (cidrhost() etc. need modules/den/batteries/terragrunt/
# lib.nix's cidrLib, an ordinary module arg den's aspect-content functions
# can't see — see modules/den/routerosDevices/rb5009.nix), and the thin, shared
# ros-<stack> aspects (modules/den/aspects/routeros/*.nix) just look it up by
# stack name. Cluster-owned stacks need no arithmetic, so their content
# functions read cluster.* directly instead — no reserved-key indirection.
{
  lib,
  den,
  ...
}:
let
  hcl = import ./_render-lib.nix { inherit lib; };

  # One real evalModules pass per stack-module (not one shared call across
  # the whole includes chain — every aspect sets the same `stack` key to a
  # different value, which a single shared evalModules call rejects as
  # "option `stack' is defined multiple times") so a deferred
  # quirk-consuming aspect actually gets invoked instead of read as raw,
  # unresolved data. The freeform type lets stack aspects keep returning
  # plain attrsets — no options.* declarations needed anywhere.
  #
  # `modules` isn't only real per-aspect content — den also injects an
  # anonymous, key-less companion module alongside any quirk-requesting
  # entry (requests `config` itself, to ambiguity-check the quirk against
  # sibling producers; meant to run inside den's own full-scope evalModules
  # pass, not this isolated per-stack one — evaluating it here recurses
  # forever). Real per-aspect content always carries a `key` (confirmed
  # empirically); skip anything without one.
  instantiateStacks =
    modules: specialArgs:
    lib.listToAttrs (
      map (
        m:
        let
          evaluated = lib.evalModules {
            modules = [
              (builtins.head m.imports)
              { _module.freeformType = lib.types.attrsOf lib.types.raw; }
            ];
            inherit specialArgs;
          };
          content = evaluated.config;
        in
        lib.nameValuePair content.stack (removeAttrs content [ "stack" ])
      ) (builtins.filter (m: m ? key) modules)
    );
in
{
  den.reservedKeys = [ "terragruntInputs" ];

  den.classes."terragrunt-stacks" = { };

  den.policies.routeros-device-to-terragrunt =
    {
      routerosDevice,
      # Quirks a "terragrunt-stacks" content function might request. Policies
      # (unlike class content functions) receive already-resolved den
      # context directly, so `firewall` here is the plain, concrete,
      # pipe-collected list (see routeros-device-collect-firewall in
      # modules/den/policies/pipes.nix) — not a deferred/curried value. It's
      # threaded into `specialArgs` below so a real per-stack evalModules
      # pass can hand it straight to whichever content function names it,
      # without falling back to `config._module.args.<name>` (which would
      # recurse forever inside our isolated per-stack evalModules call,
      # since nothing in that tiny module list defines it).
      firewall ? [ ],
      ...
    }:
    [
      (den.lib.policy.instantiate {
        name = "${routerosDevice.name}-terragrunt";
        class = "terragrunt-stacks";
        instantiate = { modules, ... }: instantiateStacks modules { inherit routerosDevice firewall; };
        intoAttr = [
          "terragruntStacks"
          "network"
          routerosDevice.name
        ];
      })
    ];

  den.policies.cluster-to-terragrunt =
    { cluster, ... }:
    [
      (den.lib.policy.instantiate {
        name = "${cluster.name}-terragrunt";
        class = "terragrunt-stacks";
        instantiate = { modules, ... }: instantiateStacks modules { inherit cluster hcl; };
        intoAttr = [
          "terragruntStacks"
          "k3s"
          cluster.name
        ];
      })
    ];

  den.schema.routerosDevice.includes = [ den.policies.routeros-device-to-terragrunt ];
  den.schema.cluster.includes = [ den.policies.cluster-to-terragrunt ];
}
