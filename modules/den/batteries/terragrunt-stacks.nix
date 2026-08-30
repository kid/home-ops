# terragrunt-stacks class + collection policy.
#
# Modeled on nixopslab's modules/terranix/collect.nix host-to-terranix
# policy: registers "terragrunt-stacks" as an aspect content class directly
# on den.classes (no private namespace — see AGENTS.md), and collects it —
# across a routerosDevice's aspect-includes chain
# (den.aspects.<routerosDevice>.includes = [ den.aspects.routeros.base
# den.aspects.routeros.capsman ... ]) — into
# config.flake.terragruntStacks.<routerosDevice>.<stack>.
#
# `terragruntInputs` is a reserved (non-class) aspect key: each device's own
# self-aspect (modules/den/routerosDevices/*.nix) precomputes its per-stack
# {dependsOn, inputs} data there (cidrhost() etc. need modules/network/
# lib.nix's cidrLib, an ordinary module arg den's aspect-content functions
# can't see — see modules/den/routerosDevices/rb5009.nix), and the thin, shared
# ros-<stack> aspects (modules/den/aspects/routeros/*.nix) just look it up by
# stack name.
{
  lib,
  den,
  ...
}:
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
        # Each item in `modules` arrives den-wrapped as a NixOS-module-style
        # { imports = [ <our plain attrset, or a lib.setFunctionArgs-curried
        # function if the aspect requested a den.quirks value> ]; ... }.
        # Route each one through its own real evalModules pass (one per
        # stack-module, not one shared call across the device's whole stack
        # list — every aspect sets the same `stack` key to a different value,
        # which a single shared evalModules call rejects as "option `stack'
        # is defined multiple times") so a deferred quirk-consuming aspect
        # actually gets invoked instead of read as raw, unresolved data. The
        # freeform type lets ros-*.nix content functions keep returning
        # plain attrsets — no options.* declarations needed anywhere.
        instantiate =
          { modules, ... }:
          lib.listToAttrs (
            map (
              m:
              let
                # `modules` isn't only real per-aspect content — den also
                # injects an anonymous, key-less companion module alongside
                # any quirk-requesting entry (requests `config` itself, to
                # ambiguity-check the quirk against sibling producers; meant
                # to run inside den's own full-scope evalModules pass, not
                # this isolated per-stack one — evaluating it here recurses
                # forever). Real per-aspect content always carries a `key`
                # (confirmed empirically: every actual ros-*.nix stack entry
                # has one, the auxiliary validator doesn't); skip anything
                # without one.
                evaluated = lib.evalModules {
                  modules = [
                    (builtins.head m.imports)
                    { _module.freeformType = lib.types.attrsOf lib.types.raw; }
                  ];
                  specialArgs = {
                    inherit routerosDevice firewall;
                  };
                };
                content = evaluated.config;
              in
              lib.nameValuePair content.stack (removeAttrs content [ "stack" ])
            ) (builtins.filter (m: m ? key) modules)
          );
        intoAttr = [
          "terragruntStacks"
          routerosDevice.name
        ];
      })
    ];

  den.schema.routerosDevice.includes = [ den.policies.routeros-device-to-terragrunt ];
}
