# terragrunt-stacks class + collection policy.
#
# Modeled on nixopslab's modules/terranix/collect.nix host-to-terranix
# policy: registers "terragrunt-stacks" as an aspect content class directly
# on den.classes (no private namespace — see AGENTS.md), and collects it —
# across a device's aspect-includes chain (den.aspects.<device>.includes = [
# den.aspects.ros-base den.aspects.ros-capsman ... ]) — into
# config.flake.terragruntStacks.<device>.<stack>.
#
# `terragruntInputs` is a reserved (non-class) aspect key: each device's own
# self-aspect (modules/devices/*.nix) precomputes its per-stack {dependsOn,
# inputs} data there (cidrhost() etc. need modules/network/lib.nix's
# cidrLib, an ordinary module arg den's aspect-content functions can't see —
# see modules/devices/rb5009.nix), and the thin, shared ros-<stack> aspects
# (modules/network/aspects/ros-*.nix) just look it up by stack name.
{
  lib,
  den,
  ...
}:
{
  den.reservedKeys = [ "terragruntInputs" ];

  den.classes."terragrunt-stacks" = { };

  den.policies.device-to-terragrunt =
    { device, ... }:
    [
      (den.lib.policy.instantiate {
        name = "${device.name}-terragrunt";
        class = "terragrunt-stacks";
        # Each item in `modules` arrives den-wrapped as a NixOS-module-style
        # { imports = [ <our plain attrset> ]; ... } (den hands this list
        # straight to consumers like terranix's own lib.evalModules-based
        # `modules` option; we want the plain data instead).
        # TODO: this reads `m.imports`'s head as already-resolved plain data,
        # which breaks the moment any ros-*.nix content function requests a
        # den.quirks value as a named parameter — den defers that aspect's
        # content into a wrapped module (__functor/__functionArgs) meant to
        # be finalized by a real lib.evalModules pass, which this function
        # never performs (confirmed empirically, see AGENTS.md). Revisit by
        # routing `modules` through lib.evalModules here before extracting
        # per-stack content, so quirks/pipe.collect can reach ros-*.nix.
        instantiate =
          { modules, ... }:
          lib.listToAttrs (
            map (
              m:
              let
                content = builtins.head m.imports;
              in
              lib.nameValuePair content.stack (removeAttrs content [ "stack" ])
            ) modules
          );
        intoAttr = [
          "terragruntStacks"
          device.name
        ];
      })
    ];

  den.schema.device.includes = [ den.policies.device-to-terragrunt ];
}
